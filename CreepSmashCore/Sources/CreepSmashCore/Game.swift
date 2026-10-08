/// Deterministic simulation of all boards.
///
/// Each device holds its own instance, executes the same commands at the same tick and thus reaches the
/// same state (lockstep). Only integer arithmetic is used. The order in `step()` is part
/// of the game rules and must not differ between versions that play against each other.
public final class Game {
    public let rules: Rules
    public let map: GameMap
    /// Next tick to execute (= number of ticks already computed).
    public private(set) var tick: Int = 0
    public internal(set) var players: [PlayerBoard]
    /// Events of the most recently computed tick.
    public private(set) var events: [GameEvent] = []
    public private(set) var isFinished = false
    public private(set) var winner: Int?

    private var nextId = 1
    private var scheduled: [Int: [ScheduledCommand]] = [:]

    public init(map: GameMap, playerNames: [String], rules: Rules = .standard) {
        precondition(!playerNames.isEmpty, "at least one player")
        self.rules = rules
        self.map = map
        self.players = playerNames.enumerated().map { index, name in
            PlayerBoard(index: index, name: name, credits: rules.startCredits,
                        income: rules.startIncome, lives: rules.startLives)
        }
    }

    // MARK: - Queries

    public var isStarted: Bool { tick >= rules.startTick }
    public var ticksUntilStart: Int { max(0, rules.startTick - tick) }

    /// Ticks until the next income payment (0 = in the next tick).
    public var ticksUntilIncome: Int {
        if tick <= rules.startTick { return rules.startTick - tick }
        let r = (tick - rules.startTick) % rules.incomeIntervalTicks
        return r == 0 ? 0 : rules.incomeIntervalTicks - r
    }

    public var alivePlayers: [Int] { players.indices.filter { !players[$0].isDead } }

    /// Player on whose board the creeps of `player` walk (the next living player in the ring).
    public func opponent(of player: Int) -> Int? { nextAlivePlayer(after: player, excluding: player) }

    /// Living opponents of `player` in ring order, starting with the next one.
    public func opponents(of player: Int) -> [Int] {
        let n = players.count
        return (1..<max(n, 1)).map { (player + $0) % n }.filter { !players[$0].isDead }
    }

    /// Number of boards a creep sent by `player` lands on with the current send mode.
    public func recipientCount(of player: Int) -> Int {
        players[player].sendMode == .all ? max(1, opponents(of: player).count) : 1
    }

    public func scheduledCommands(player: Int) -> [ScheduledCommand] {
        scheduled.values.flatMap { $0 }.filter { $0.player == player }
    }

    /// Credits that scheduled, not yet executed commands are expected to cost.
    public func reservedCredits(player: Int) -> Int {
        scheduledCommands(player: player).reduce(0) { sum, c in
            switch c.command {
            case let .buildTower(kind, _): return sum + kind.stats(level: 1).price
            case let .upgradeTower(id): return sum + (players[player].tower(id: id)?.nextLevelPrice ?? 0)
            case let .sendCreeps(type, count):
                return sum + type.stats.price * min(max(count, 1), rules.waveSize) * recipientCount(of: player)
            case .sellTower, .setStrategy, .surrender, .setSendMode: return sum
            }
        }
    }

    // MARK: - Commands

    public func schedule(_ command: ScheduledCommand) {
        precondition(command.tick >= tick, "command for tick \(command.tick) arrives after tick \(tick)")
        precondition(players.indices.contains(command.player), "unknown player")
        scheduled[command.tick, default: []].append(command)
    }

    // MARK: - Simulation

    public func step() {
        events.removeAll(keepingCapacity: true)
        guard !isFinished else { return }

        if var commands = scheduled.removeValue(forKey: tick) {
            commands.sort { ($0.player, $0.sequence) < ($1.player, $1.sequence) }
            for command in commands { execute(command) }
        }

        var arrivals: [(board: Int, creep: Creep)] = []
        for p in players.indices {
            if !players[p].isDead { updateTowers(p) }
            updateCreeps(p, arrivals: &arrivals)
        }
        for arrival in arrivals { transfer(arrival.creep, from: arrival.board) }

        payIncome()
        checkGameOver()
        tick += 1
    }

    // MARK: Executing commands

    private func execute(_ scheduled: ScheduledCommand) {
        let p = scheduled.player
        let command = scheduled.command
        func reject(_ reason: RejectReason) {
            events.append(.commandRejected(player: p, command: command, reason: reason))
        }
        guard !players[p].isDead else { return reject(.playerDead) }
        if command == .surrender {
            players[p].lives = 0
            playerDied(p)
            return
        }
        guard isStarted else { return reject(.notStarted) }

        switch command {
        case let .buildTower(kind, cell):
            guard map.isBuildable(cell) else { return reject(.cellNotBuildable) }
            guard players[p].tower(at: cell) == nil else { return reject(.cellOccupied) }
            let price = kind.stats(level: 1).price
            guard players[p].credits >= price else { return reject(.notEnoughCredits) }
            players[p].credits -= price
            let tower = Tower(id: makeId(), kind: kind, cell: cell,
                              activity: .building(remaining: rules.actionTicks),
                              strategy: kind.defaultStrategy, totalPrice: price)
            players[p].towers.append(tower)
            events.append(.towerBuilt(player: p, towerId: tower.id))

        case let .upgradeTower(id):
            guard let i = players[p].towers.firstIndex(where: { $0.id == id }) else { return reject(.unknownTower) }
            guard players[p].towers[i].activity.isReady else { return reject(.towerBusy) }
            guard let price = players[p].towers[i].nextLevelPrice else { return reject(.maxLevel) }
            guard players[p].credits >= price else { return reject(.notEnoughCredits) }
            players[p].credits -= price
            players[p].towers[i].activity = .upgrading(remaining: rules.actionTicks)

        case let .sellTower(id):
            guard let i = players[p].towers.firstIndex(where: { $0.id == id }) else { return reject(.unknownTower) }
            guard players[p].towers[i].activity.isReady else { return reject(.towerBusy) }
            players[p].towers[i].activity = .selling(remaining: rules.actionTicks)

        case let .setStrategy(id, strategy, locked):
            guard let i = players[p].towers.firstIndex(where: { $0.id == id }) else { return reject(.unknownTower) }
            guard players[p].towers[i].activity.isReady else { return reject(.towerBusy) }
            players[p].towers[i].activity = .retargeting(remaining: rules.actionTicks, strategy: strategy, locked: locked)

        case let .sendCreeps(type, count):
            let targets: [Int]
            let others = opponents(of: p)
            guard !others.isEmpty else { return reject(.noTarget) }
            switch players[p].sendMode {
            case .next: targets = [others[0]]
            case .all: targets = others
            case .random: targets = [others[randomIndex(others.count, salt: p)]]
            }
            let price = type.stats.price * targets.count
            let n = min(max(count, 1), rules.waveSize, players[p].credits / price)
            guard n >= 1 else { return reject(.notEnoughCredits) }
            players[p].credits -= n * price
            players[p].income += n * type.stats.income * targets.count
            players[p].healthSent += n * type.stats.health * targets.count
            let start = map.position(segment: 0, step: 0)
            for target in targets {
                for i in 0..<n {
                    let creep = Creep(id: makeId(), type: type, sender: p, health: type.stats.health,
                                      speed: type.stats.speed * Board.milli,
                                      activeFromTick: tick + i * rules.waveSpacingTicks,
                                      x: start.x, y: start.y)
                    players[target].creeps.append(creep)
                }
                events.append(.creepsSent(from: p, to: target, type: type, count: n))
            }

        case let .setSendMode(mode):
            players[p].sendMode = mode

        case .surrender:
            break  // handled above
        }
    }

    // MARK: Creeps

    private func updateCreeps(_ p: Int, arrivals: inout [(board: Int, creep: Creep)]) {
        var i = 0
        while i < players[p].creeps.count {
            var c = players[p].creeps[i]
            guard c.isActive(at: tick) else { i += 1; continue }

            if c.slowTicks > 0 {
                c.slowTicks -= 1
                if c.slowTicks == 0 { c.speed = c.baseSpeed }
            }
            let maxHealth = c.stats.health
            if c.health < maxHealth {
                c.health = min(c.health + c.stats.regeneration, maxHealth)
            }

            c.totalSteps += c.speed
            c.step += c.speed
            if c.step > Board.segmentSteps {
                c.step -= Board.segmentSteps
                c.segment += 1
                if c.segment >= map.path.count - 1 {
                    c.segment = 0
                    players[p].creeps.remove(at: i)
                    arrivals.append((p, c))
                    continue
                }
            }
            (c.x, c.y) = map.position(segment: c.segment, step: c.step)
            players[p].creeps[i] = c
            i += 1
        }
    }

    /// Creep has reached the end of the path: subtract a life and pass it on to the next player.
    private func transfer(_ creep: Creep, from p: Int) {
        if !players[p].isDead {
            players[p].lives -= 1
            if players.indices.contains(creep.sender) { players[creep.sender].livesTaken += 1 }
            events.append(.creepEscaped(player: p, creepId: creep.id, type: creep.type, sender: creep.sender))
            if players[p].isDead { playerDied(p) }
        }
        guard let target = nextAlivePlayer(after: p, excluding: creep.sender) else { return }
        var c = creep
        (c.x, c.y) = map.position(segment: c.segment, step: c.step)
        players[target].creeps.append(c)
    }

    /// Next living player in the ring after `p`, never `excluding`. Includes `p` itself at the end of the ring.
    private func nextAlivePlayer(after p: Int, excluding: Int) -> Int? {
        let n = players.count
        for k in 1...n {
            let q = (p + k) % n
            if q != excluding && !players[q].isDead { return q }
        }
        return nil
    }

    // MARK: Tower

    private func updateTowers(_ p: Int) {
        var i = 0
        while i < players[p].towers.count {
            if updateTower(p, index: i) { i += 1 }
        }
    }

    /// - Returns: `false` if the tower was removed.
    private func updateTower(_ p: Int, index i: Int) -> Bool {
        var tower = players[p].towers[i]

        switch tower.activity {
        case .ready:
            break
        case let .building(remaining):
            if remaining > 1 {
                players[p].towers[i].activity = .building(remaining: remaining - 1)
                return true
            }
            tower.activity = .ready
        case let .upgrading(remaining):
            if remaining > 1 {
                tower.activity = .upgrading(remaining: remaining - 1)
            } else {
                tower.level += 1
                tower.totalPrice += tower.stats.price
                tower.cooldown = tower.stats.reloadTicks
                tower.activity = .ready
                events.append(.towerUpgraded(player: p, towerId: tower.id, level: tower.level))
            }
        case let .selling(remaining):
            if remaining > 1 {
                tower.activity = .selling(remaining: remaining - 1)
            } else {
                let refund = tower.sellValue(rules: rules)
                players[p].credits += refund
                players[p].towers.remove(at: i)
                events.append(.towerSold(player: p, towerId: tower.id, refund: refund))
                return false
            }
        case let .retargeting(remaining, strategy, locked):
            if remaining > 1 {
                tower.activity = .retargeting(remaining: remaining - 1, strategy: strategy, locked: locked)
            } else {
                tower.strategy = strategy
                tower.locked = locked
                tower.lastTargetId = nil
                tower.activity = .ready
            }
        }

        // A tower does not fire while it is built (see above) or upgraded; rockets already in the air
        // fly on. As in the original, it does fire during sale and strategy change.
        if case .upgrading = tower.activity {
            updateProjectiles(p, tower: &tower)
            players[p].towers[i] = tower
            return true
        }
        if tower.cooldown > 0 { tower.cooldown -= 1 }
        if tower.cooldown == 0, let target = findTarget(p, tower: &tower) {
            attack(p, tower: &tower, targetIndex: target)
            tower.cooldown = tower.stats.reloadTicks
        }
        updateProjectiles(p, tower: &tower)
        players[p].towers[i] = tower
        return true
    }

    private func findTarget(_ p: Int, tower: inout Tower) -> Int? {
        let creeps = players[p].creeps
        let center = Board.center(of: tower.cell)
        let range = tower.stats.range * Board.milli
        let rangeSquared = range * range
        func distance(_ c: Creep) -> Int { distanceSquared(c.x, c.y, center.x, center.y) }
        func inRange(_ c: Creep) -> Bool { c.isActive(at: tick) && distance(c) < rangeSquared }

        if tower.locked, let last = tower.lastTargetId,
           let index = creeps.firstIndex(where: { $0.id == last }), inRange(creeps[index]) {
            return index
        }

        var found: Int?
        for (index, c) in creeps.enumerated() where inRange(c) {
            guard let f = found else { found = index; continue }
            let o = creeps[f]
            let better: Bool
            // On a tie, the later creep wins (as in the original).
            switch tower.strategy {
            case .closest: better = distance(c) <= distance(o)
            case .farthest: better = c.totalSteps >= o.totalSteps
            case .fastest: better = (c.stats.slowImmune ? 0 : 1, c.speed) >= (o.stats.slowImmune ? 0 : 1, o.speed)
            case .strongest: better = c.health >= o.health
            case .weakest: better = c.health <= o.health
            }
            if better { found = index }
        }
        tower.lastTargetId = found.map { creeps[$0].id }
        return found
    }

    private func attack(_ p: Int, tower: inout Tower, targetIndex: Int) {
        let s = tower.stats
        let target = players[p].creeps[targetIndex]
        switch s.weapon {
        case .laser, .slower:
            events.append(.laserShot(player: p, towerId: tower.id, targetId: target.id, splashTargetIds: []))
            if damage(p, index: targetIndex, amount: s.damage), s.weapon == .slower {
                slow(p, index: targetIndex, stats: s)
            }
        case .splashLaser, .slowerSplash:
            let hits = splash(p, x: target.x, y: target.y, stats: s, slowing: s.weapon == .slowerSplash)
            events.append(.laserShot(player: p, towerId: tower.id, targetId: target.id,
                                     splashTargetIds: hits.filter { $0 != target.id }))
        case .rocket:
            let center = Board.center(of: tower.cell)
            tower.projectiles.append(Projectile(id: makeId(), targetId: target.id,
                                                x: center.x, y: center.y, stepLength: 75))
            events.append(.rocketLaunched(player: p, towerId: tower.id))
        }
    }

    /// Splash damage around (x, y). - Returns: IDs of all creeps hit.
    @discardableResult
    private func splash(_ p: Int, x: Int, y: Int, stats s: TowerStats, slowing: Bool) -> [Int] {
        let radius = s.splashRadius * Board.milli
        let hitIds = players[p].creeps
            .filter { $0.isActive(at: tick) && distanceSquared($0.x, $0.y, x, y) < radius * radius }
            .map(\.id)
        for id in hitIds {
            guard let j = players[p].creeps.firstIndex(where: { $0.id == id }) else { continue }
            let c = players[p].creeps[j]
            let dist = isqrt(distanceSquared(c.x, c.y, x, y))
            let amount = s.damage - s.damage * s.splashReductionPermille * dist / (1000 * radius)
            if damage(p, index: j, amount: amount), slowing {
                slow(p, index: j, stats: s)
            }
        }
        return hitIds
    }

    private func updateProjectiles(_ p: Int, tower: inout Tower) {
        var k = 0
        while k < tower.projectiles.count {
            var shot = tower.projectiles[k]
            if shot.hasArrived {
                let s = tower.stats
                let hits = splash(p, x: shot.x, y: shot.y, stats: s, slowing: false)
                events.append(.explosion(player: p, x: shot.x, y: shot.y, radius: s.splashRadius, hitIds: hits))
                tower.projectiles.remove(at: k)
                continue
            }
            var targetIndex = players[p].creeps.firstIndex { $0.id == shot.targetId && $0.isActive(at: tick) }
            if targetIndex == nil {
                // Target is dead or gone: pick a new target by strategy, otherwise the rocket fizzles out.
                targetIndex = findTarget(p, tower: &tower)
                if let t = targetIndex { shot.targetId = players[p].creeps[t].id }
            }
            guard let t = targetIndex else {
                tower.projectiles.remove(at: k)
                continue
            }
            let target = players[p].creeps[t]
            let dx = target.x - shot.x, dy = target.y - shot.y
            let r = isqrt(dx * dx + dy * dy)
            if r > 2 * Board.milli && shot.stepLength < r {
                shot.x += dx * shot.stepLength / r
                shot.y += dy * shot.stepLength / r
                shot.stepLength += 30
            } else {
                shot.x = target.x
                shot.y = target.y
                shot.hasArrived = true
            }
            tower.projectiles[k] = shot
            k += 1
        }
    }

    /// - Returns: `true` if the creep survives.
    @discardableResult
    private func damage(_ p: Int, index: Int, amount: Int) -> Bool {
        // Statistics: only the damage that actually takes health away counts.
        players[p].damageDealt += max(0, min(amount, players[p].creeps[index].health))
        players[p].creeps[index].health -= amount
        guard players[p].creeps[index].health <= 0 else { return true }
        let c = players[p].creeps.remove(at: index)
        if !players[p].isDead { players[p].credits += c.stats.bounty }
        events.append(.creepKilled(player: p, creepId: c.id, type: c.type, x: c.x, y: c.y, bounty: c.stats.bounty))
        return false
    }

    private func slow(_ p: Int, index: Int, stats s: TowerStats) {
        let c = players[p].creeps[index]
        guard !c.stats.slowImmune else { return }
        let slowed = c.baseSpeed * (1000 - s.slowPermille) / 1000
        if c.speed > slowed {
            players[p].creeps[index].speed = slowed
            players[p].creeps[index].slowTicks = s.slowTicks
        }
    }

    // MARK: Income, game over

    private func payIncome() {
        guard tick >= rules.startTick, (tick - rules.startTick) % rules.incomeIntervalTicks == 0 else { return }
        for p in players.indices where !players[p].isDead {
            players[p].credits += players[p].income
            events.append(.incomePaid(player: p, amount: players[p].income))
        }
    }

    private func playerDied(_ p: Int) {
        let rank = alivePlayers.count + 1
        players[p].rank = rank
        events.append(.playerDied(player: p, rank: rank))
    }

    private func checkGameOver() {
        guard players.count >= 2 else { return }
        let alive = alivePlayers
        guard alive.count <= 1 else { return }
        isFinished = true
        winner = alive.first
        if let w = winner { players[w].rank = 1 }
        events.append(.gameFinished(winner: winner))
    }

    /// Deterministic "random" number in 0..<n from the game state, so every device draws the same.
    private func randomIndex(_ n: Int, salt: Int) -> Int {
        var x = UInt64(truncatingIfNeeded: tick) &* 0x9E37_79B9_7F4A_7C15
        x ^= UInt64(truncatingIfNeeded: nextId) &* 0xBF58_476D_1CE4_E5B9
        x ^= UInt64(truncatingIfNeeded: salt) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        x = x &* 0xD6E8_FEB8_6659_FD93
        x ^= x >> 32
        return Int(x % UInt64(n))
    }

    private func makeId() -> Int {
        defer { nextId += 1 }
        return nextId
    }

    // MARK: - Checksum

    /// Checksum over the entire game state; must be identical on all devices.
    public func checksum() -> UInt64 {
        var h = Checksum()
        h.add(tick)
        h.add(nextId)
        h.add(isFinished)
        for p in players {
            h.add(p.credits); h.add(p.income); h.add(p.lives); h.add(p.livesTaken); h.add(p.rank ?? -1)
            h.add(SendMode.allCases.firstIndex(of: p.sendMode) ?? 0)
            h.add(p.creeps.count)
            for c in p.creeps {
                h.add(c.id); h.add(c.type.rawValue); h.add(c.sender); h.add(c.health); h.add(c.speed)
                h.add(c.slowTicks); h.add(c.segment); h.add(c.step); h.add(c.totalSteps)
                h.add(c.activeFromTick); h.add(c.x); h.add(c.y)
            }
            h.add(p.towers.count)
            for t in p.towers {
                h.add(t.id); h.add(t.kind.rawValue); h.add(t.level); h.add(t.cell.x); h.add(t.cell.y)
                switch t.activity {
                case .ready: h.add(0)
                case let .building(r): h.add(1); h.add(r)
                case let .upgrading(r): h.add(2); h.add(r)
                case let .selling(r): h.add(3); h.add(r)
                case let .retargeting(r, s, l): h.add(4); h.add(r); h.add(s.index); h.add(l)
                }
                h.add(t.cooldown); h.add(t.strategy.index); h.add(t.locked); h.add(t.lastTargetId ?? -1)
                h.add(t.totalPrice)
                h.add(t.projectiles.count)
                for s in t.projectiles {
                    h.add(s.id); h.add(s.targetId); h.add(s.x); h.add(s.y); h.add(s.stepLength); h.add(s.hasArrived)
                }
            }
        }
        return h.value
    }
}

extension TargetStrategy {
    var index: Int { Self.allCases.firstIndex(of: self)! }
}
