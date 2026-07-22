###############################################################################
# package_ip_all.tcl
#
# Orchestrateur : packagee les 2 IP du depot (AXI4-Lite et standalone) en
# une seule invocation Vivado, en reutilisant tel quel package_ip_axi.tcl et
# package_ip_standalone.tcl (pas de duplication de la logique de packaging).
#
# Usage (depuis la racine du depot, ou n'importe ou) :
#   vivado -mode batch -source tcl/package_ip_all.tcl \
#       -tclargs [part] [repo_dir_axi] [repo_dir_standalone]
#
# Arguments optionnels :
#   part                 : partie Vivado cible pour les 2 IP. Par defaut
#                           xck26-sfvc784-2LV-c (cf. note dans
#                           package_ip_axi.tcl sur le part number KV260/KR260).
#   repo_dir_axi         : repertoire de sortie de l'IP AXI4-Lite.
#                           Par defaut ./ip_repo_axi
#   repo_dir_standalone  : repertoire de sortie de l'IP standalone.
#                           Par defaut ./ip_repo_standalone
#
# Chaque IP est packagee dans son propre projet Vivado temporaire jetable
# (_pkg_build_axi / _pkg_build_standalone, definis dans les scripts
# respectifs), qui est ferme (close_project) avant de passer a la suivante.
# Une erreur sur l'une des deux IP n'empeche pas la tentative de packaging
# de l'autre ; le script se termine avec un code de sortie non-nul si au
# moins une des deux a echoue.
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

set overall_ok 1

puts "\n=== \[1/2\] Packaging IP AXI4-Lite (pwm_fan_thermal_axi_v1_0) ===\n"
set argv [list $part $repo_dir_axi]
if {[catch {source [file join $script_dir "package_ip_axi.tcl"]} err]} {
    puts "ERREUR lors du packaging de l'IP AXI4-Lite : $err"
    set overall_ok 0
}

puts "\n=== \[2/2\] Packaging IP standalone (pwm_fan_thermal_standalone) ===\n"
set argv [list $part $repo_dir_standalone]
if {[catch {source [file join $script_dir "package_ip_standalone.tcl"]} err]} {
    puts "ERREUR lors du packaging de l'IP standalone : $err"
    set overall_ok 0
}

if {$overall_ok} {
    puts "\n=== Termine : 2 IP packagees avec succes ==="
    puts "  AXI4-Lite  : [file normalize $repo_dir_axi]"
    puts "  Standalone : [file normalize $repo_dir_standalone]"
    puts "Pensez a ajouter les 2 repertoires au repository IP de votre projet :"
    puts "  set_property ip_repo_paths \[list [file normalize $repo_dir_axi] [file normalize $repo_dir_standalone]\] \[current_project\]"
    puts "  update_ip_catalog"
} else {
    puts "\n=== Termine avec au moins une erreur, voir messages ci-dessus ==="
    exit 1
}
