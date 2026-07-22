###############################################################################
# package_ip_all.tcl
#
# Orchestrateur : packagee les 3 IP du depot (AXI4-Lite, standalone
# thermique, open-loop) en une seule invocation Vivado, en reutilisant tel
# quel package_ip_axi.tcl / package_ip_standalone.tcl /
# package_ip_open_loop.tcl (pas de duplication de la logique de packaging).
#
# Usage (depuis la racine du depot, ou n'importe ou) :
#   vivado -mode batch -source tcl/package_ip_all.tcl \
#       -tclargs [part] [repo_dir_axi] [repo_dir_standalone] [repo_dir_open_loop]
#
# Arguments optionnels :
#   part                 : partie Vivado cible pour les 3 IP. Par defaut
#                           xck26-sfvc784-2LV-c (cf. note dans
#                           package_ip_axi.tcl sur le part number KV260/KR260).
#   repo_dir_axi         : repertoire de sortie de l'IP AXI4-Lite.
#                           Par defaut ./ip_repo_axi
#   repo_dir_standalone  : repertoire de sortie de l'IP standalone thermique.
#                           Par defaut ./ip_repo_standalone
#   repo_dir_open_loop   : repertoire de sortie de l'IP open-loop (rapport
#                           cyclique fixe, sans temperature). Par defaut
#                           ./ip_repo_open_loop
#
# Chaque IP est packagee dans son propre projet Vivado temporaire jetable
# (_pkg_build_axi / _pkg_build_standalone / _pkg_build_open_loop, definis
# dans les scripts respectifs), qui est ferme (close_project) avant de
# passer a la suivante. Une erreur sur l'une des IP n'empeche pas la
# tentative de packaging des autres ; le script se termine avec un code de
# sortie non-nul si au moins une a echoue.
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

set overall_ok 1

puts "\n=== \[1/3\] Packaging IP AXI4-Lite (pwm_fan_thermal_axi_v1_0) ===\n"
set argv [list $part $repo_dir_axi]
if {[catch {source [file join $script_dir "package_ip_axi.tcl"]} err]} {
    puts "ERREUR lors du packaging de l'IP AXI4-Lite : $err"
    set overall_ok 0
}

puts "\n=== \[2/3\] Packaging IP standalone thermique (pwm_fan_thermal_standalone) ===\n"
set argv [list $part $repo_dir_standalone]
if {[catch {source [file join $script_dir "package_ip_standalone.tcl"]} err]} {
    puts "ERREUR lors du packaging de l'IP standalone : $err"
    set overall_ok 0
}

puts "\n=== \[3/3\] Packaging IP open-loop (pwm_fan_open_loop) ===\n"
set argv [list $part $repo_dir_open_loop]
if {[catch {source [file join $script_dir "package_ip_open_loop.tcl"]} err]} {
    puts "ERREUR lors du packaging de l'IP open-loop : $err"
    set overall_ok 0
}

if {$overall_ok} {
    puts "\n=== Termine : 3 IP packagees avec succes ==="
    puts "  AXI4-Lite  : [file normalize $repo_dir_axi]"
    puts "  Standalone : [file normalize $repo_dir_standalone]"
    puts "  Open-loop  : [file normalize $repo_dir_open_loop]"
    puts "Pensez a ajouter les 3 repertoires au repository IP de votre projet :"
    puts "  set_property ip_repo_paths \[list [file normalize $repo_dir_axi] [file normalize $repo_dir_standalone] [file normalize $repo_dir_open_loop]\] \[current_project\]"
    puts "  update_ip_catalog"
} else {
    puts "\n=== Termine avec au moins une erreur, voir messages ci-dessus ==="
    exit 1
}
