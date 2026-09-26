# XSim batch script. Every run starts from an independent simulation snapshot.
run 300 ns
open_saif activity.saif
log_saif [get_objects -r /tb_power_temporal_reuse/dut/*]
run $::env(REUSE_POWER_WINDOW_NS) ns
close_saif
puts "POWER_SAIF_PASS"
quit
