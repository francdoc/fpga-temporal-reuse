# Arty Z7-10 Rev. D: Digilent reference manual section 11 and Rev. D schematic.
# H16/LVCMOS33 also matches the installed Digilent board pin definition.
# The Ethernet PHY supplies the 125 MHz PL clock at H16.
set_property PACKAGE_PIN H16 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
create_clock -name sys_clk -period 8.000 [get_ports sys_clk]
# Clocking Wizard supplies the derived 100 MHz clock constraint.
