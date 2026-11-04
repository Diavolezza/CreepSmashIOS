#!/bin/bash
# Exports the power tables of all traces in build/energy/<label>/ as XML next to them.
D=build/energy/${1:-before}
for t in "$D"/*.trace; do
  n=$(basename "$t" .trace)
  for s in SystemPowerLevel ProcessSubsystemPowerImpact metal-perf-overview-power-system-metric ProcessCPUUsage; do
    xcrun xctrace export --input "$t" --xpath "/trace-toc/run[@number=\"1\"]/data/table[@schema=\"$s\"]" > "$D/$n.$s.xml" 2>/dev/null
  done
  ls -la "$D/$n".*.xml | awk '{print $5, $9}'
done
