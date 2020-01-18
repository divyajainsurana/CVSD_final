#read file
read_verilog MEMC.v
#current design
current_design MEMC
#resolve design reference
link
check_design
#constrains
source MEMC_DC.sdc
#Get gate level circuit
compile -map_effort medium
#Check conditions
report_timing -path full -delay max -max_paths 1 -nworst1
report_power
report_area -nosplit
#save gate level netlist
write -hierarchy -format verilog -output MEM_syn.v
#save timing information
write_sdf -version 2.1 Mem_syn.sdf
