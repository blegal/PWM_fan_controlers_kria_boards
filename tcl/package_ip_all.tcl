###############################################################################
# package_ip_all.tcl
#
# Orchestrateur : packagee les 5 IP du depot (AXI4-Lite, standalone
# thermique, open-loop, build info, PWM AXI-Lite) en une seule invocation
# Vivado, en reutilisant tel quel package_ip_axi.tcl /
# package_ip_standalone.tcl / package_ip_open_loop.tcl /
# package_ip_build_info.tcl / package_ip_pwm_axi_lite.tcl (pas de
# duplication de la logique de packaging).
#
# Usage (depuis la racine du depot, ou n'importe ou) :
#   vivado -mode batch -source tcl/package_ip_all.tcl \
#       -tclargs [part] [repo_dir_axi] [repo_dir_standalone] [repo_dir_open_loop] [repo_dir_build_info] [repo_dir_pwm_axi_lite]
#
# Arguments optionnels :
#   part                   : partie Vivado cible pour les 5 IP. Par defaut
#                             xck26-sfvc784-2LV-c (cf. note dans
#                             package_ip_axi.tcl sur le part number KV260/KR260).
#   repo_dir_axi           : repertoire de sortie de l'IP AXI4-Lite.
#                             Par defaut ./ip_repo_axi
#   repo_dir_standalone    : repertoire de sortie de l'IP standalone thermique.
#                             Par defaut ./ip_repo_standalone
#   repo_dir_open_loop     : repertoire de sortie de l'IP open-loop (rapport
#                             cyclique fixe, sans temperature). Par defaut
#                             ./ip_repo_open_loop
#   repo_dir_build_info    : repertoire de sortie de l'IP build info (date/heure
#                             de synthese + version). Par defaut
#                             ./ip_repo_build_info
#   repo_dir_pwm_axi_lite  : repertoire de sortie de l'IP PWM AXI-Lite (PERIOD/
#                             THRESHOLD). Par defaut ./ip_repo_pwm_axi_lite
#
# Chaque IP est packagee dans son propre projet Vivado temporaire jetable
# (_pkg_build_axi / _pkg_build_standalone / _pkg_build_open_loop /
# _pkg_build_build_info / _pkg_build_pwm_axi_lite, definis dans les scripts
# respectifs), qui est ferme (close_project) avant de passer a la suivante.
# Une erreur sur l'une des IP n'empeche pas la tentative de packaging des
# autres ; le script se termine avec un code de sortie non-nul si au moins
# une a echoue.
###############################################################################

set script_dir [file normalize [file dirname [info script]]]

set part [lindex $argv 0]
if {$part eq ""} {
    set part "xck26-sfvc784-2LV-c"
}

set repo_dir_axi [lindex $argv 1]
if {$repo_dir_axi eq ""} {
    set repo_dir_axi "./ip_repo_axi"
}

set repo_dir_standalone [lindex $argv 2]
if {$repo_dir_standalone eq ""} {
    set repo_dir_standalone "./ip_repo_standalone"
}

set repo_dir_open_loop [lindex $argv 3]
if {$repo_dir_open_loop eq ""} {
    set repo_dir_open_loop "./ip_repo_open_loop"
}

set repo_dir_build_info [lindex $argv 4]
if {$repo_dir_build_info eq ""} {
    set repo_dir_build_info "./ip_repo_build_info"
}

set repo_dir_pwm_axi_lite [lindex $argv 5]
if {$repo_dir_pwm_axi_lite eq ""} {
    set repo_dir_pwm_axi_lite "./ip_repo_pwm_axi_lite"
}

set overall_ok 1

puts "\n=== \[1/5\] Packaging IP AXI4-Lite (pwm_fan_thermal_axi_v1_0) ===\n"
set argv [list $part $repo_dir_axi]
if {[catch {source [file join $script_dir "package_ip_axi.tcl"]} err]} {
    puts "ERREUR lors du packaging de l'IP AXI4-Lite : $err"
    set overall_ok 0
}

puts "\n=== \[2/5\] Packaging IP standalone thermique (pwm_fan_thermal_standalone) ===\n"
set argv [list $part $repo_dir_standalone]
if {[catch {source [file join $script_dir "package_ip_standalone.tcl"]} err]} {
    puts "ERREUR lors du packaging de l'IP standalone : $err"
    set overall_ok 0
}

puts "\n=== \[3/5\] Packaging IP open-loop (pwm_fan_open_loop) ===\n"
set argv [list $part $repo_dir_open_loop]
if {[catch {source [file join $script_dir "package_ip_open_loop.tcl"]} err]} {
    puts "ERREUR lors du packaging de l'IP open-loop : $err"
    set overall_ok 0
}

puts "\n=== \[4/5\] Packaging IP build info (build_info_axi_v1_0) ===\n"
set argv [list $part $repo_dir_build_info]
if {[catch {source [file join $script_dir "package_ip_build_info.tcl"]} err]} {
    puts "ERREUR lors du packaging de l'IP build info : $err"
    set overall_ok 0
}

puts "\n=== \[5/5\] Packaging IP PWM AXI-Lite (pwm_axi_lite_v1_0) ===\n"
set argv [list $part $repo_dir_pwm_axi_lite]
if {[catch {source [file join $script_dir "package_ip_pwm_axi_lite.tcl"]} err]} {
    puts "ERREUR lors du packaging de l'IP PWM AXI-Lite : $err"
    set overall_ok 0
}

if {$overall_ok} {
    puts "\n=== Termine : 5 IP packagees avec succes ==="
    puts "  AXI4-Lite    : [file normalize $repo_dir_axi]"
    puts "  Standalone   : [file normalize $repo_dir_standalone]"
    puts "  Open-loop    : [file normalize $repo_dir_open_loop]"
    puts "  Build info   : [file normalize $repo_dir_build_info]"
    puts "  PWM AXI-Lite : [file normalize $repo_dir_pwm_axi_lite]"
    puts "Pensez a ajouter les 5 repertoires au repository IP de votre projet :"
    puts "  set_property ip_repo_paths \[list [file normalize $repo_dir_axi] [file normalize $repo_dir_standalone] [file normalize $repo_dir_open_loop] [file normalize $repo_dir_build_info] [file normalize $repo_dir_pwm_axi_lite]\] \[current_project\]"
    puts "  update_ip_catalog"
} else {
    puts "\n=== Termine avec au moins une erreur, voir messages ci-dessus ==="
    exit 1
}
