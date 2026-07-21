###############################################################################
# package_ip_standalone.tcl
#
# Package pwm_fan_thermal_standalone (aucune interface AXI, uniquement un
# port d'horloge a connecter) en IP Vivado reutilisable.
#
# Usage :
#   vivado -mode batch -source tcl/package_ip_standalone.tcl -tclargs [part] [repo_dir]
#
# Arguments optionnels :
#   part      : partie Vivado cible. Par defaut xck26-sfvc784-2LV-c
#               (cf. note sur le part number dans package_ip_axi.tcl).
#   repo_dir  : repertoire de sortie du repository IP. Par defaut
#               ./ip_repo_standalone
#
# Tous les parametres (PERIOD_CYCLES, DUTY_MIN, DUTY_MAX, T_MIN_CENTIDEG,
# T_MAX_CENTIDEG, ...) sont des generiques VHDL : ils apparaissent
# automatiquement comme parametres de personnalisation dans le Block
# Design Vivado, sans action supplementaire de ce script.
###############################################################################

set part     [lindex $argv 0]
if {$part eq ""} {
    set part "xck26-sfvc784-2LV-c"
}

set repo_dir [lindex $argv 1]
if {$repo_dir eq ""} {
    set repo_dir "./ip_repo_standalone"
}

set script_dir [file normalize [file dirname [info script]]]
set src_dir     [file normalize "$script_dir/../src"]
set build_dir   "./_pkg_build_standalone"

if {[file exists $build_dir]} {
    file delete -force $build_dir
}

create_project pkg_pwm_fan_thermal_standalone $build_dir -part $part -force

add_files -norecurse [list \
    "$src_dir/sysmon_temp_acq.vhd" \
    "$src_dir/fan_thermal_ctrl.vhd" \
    "$src_dir/pwm_fan_thermal_standalone.vhd" \
]

set_property top pwm_fan_thermal_standalone [current_fileset]
update_compile_order -fileset sources_1

file mkdir $repo_dir

ipx::package_project -root_dir $repo_dir -vendor user.org -library user \
    -taxonomy /UserIP -import_files -force

set core [ipx::current_core]

set_property name             pwm_fan_thermal_standalone                     $core
set_property display_name     "PWM Fan Thermal Standalone"                   $core
set_property description      "Controleur PWM ventilateur KV260 autonome, asservi sur la temperature SYSMON on-chip. Aucune interface AXI : seule l'horloge doit etre connectee." $core
set_property vendor_display_name "user.org"                                  $core
set_property version          "1.0"                                          $core

# Association du port d'horloge (facultatif mais recommande : permet la
# propagation automatique de la contrainte de frequence et l'auto-connexion
# dans le Block Design / IP Integrator).
catch {
    ipx::infer_bus_interface clk xilinx.com:signal:clock_rtl:1.0 $core
}

ipx::create_xgui_files      $core
ipx::update_checksums       $core
ipx::save_core              $core

close_project

puts "IP standalone packagee dans : [file normalize $repo_dir]"
puts "Pensez a l'ajouter au repository IP de votre projet :"
puts {  set_property ip_repo_paths {<chemin_absolu>/ip_repo_standalone} [current_project]}
puts {  update_ip_catalog}
