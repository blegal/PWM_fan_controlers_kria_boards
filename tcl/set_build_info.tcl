###############################################################################
# set_build_info.tcl
#
# Positionne les generics G_BUILD_DATE / G_BUILD_TIME (date/heure d'execution
# de ce script), G_VERSION_MAJOR / G_VERSION_MINOR, et G_BUILD_NUMBER sur une
# instance deja placee de l'IP build_info_axi_v1_0 (cf.
# package_ip_build_info.tcl) dans le Block Design du projet Vivado
# actuellement ouvert.
#
# A executer APRES avoir instancie l'IP dans votre Block Design, de
# preference juste avant de generer le bitstream -- par exemple via un hook
# Tcl pre-synthese (STEPS.SYNTH_DESIGN.TCL.PRE) pour que BUILD_DATE/TIME
# refletent automatiquement chaque build plutot qu'une valeur figee a la
# main une fois pour toutes.
#
# Usage interactif (Tcl Console Vivado, projet + block design deja ouverts) :
#   source tcl/set_build_info.tcl
#   set_build_info <nom_instance_bd> [version_major] [version_minor] [build_number]
#
# Usage en ligne de commande batch (le projet/block design doit deja etre
# ouvert par ailleurs -- ce script ne cree ni n'ouvre de projet) :
#   vivado -mode batch -source tcl/set_build_info.tcl \
#       -tclargs <nom_instance_bd> [version_major] [version_minor] [build_number]
#
# Si build_number est omis (ou vide), sa valeur par defaut est relue (SANS
# l'incrementer) depuis le compteur de packaging tenu par
# tcl/package_ip_build_info.tcl (cf. tcl/build_counter.tcl) : c'est ce qui
# permet de retrouver le MEME numero affiche par ce dernier script, sur
# l'instance materielle, sans avoir a le retaper a la main.
#
# Exemple :
#   set_build_info build_info_axi_v1_0_0 2 1
#   -> G_BUILD_DATE/G_BUILD_TIME = date/heure d'execution de ce script,
#      G_VERSION_MAJOR=2, G_VERSION_MINOR=1 (defaut 1/0 si omis),
#      G_BUILD_NUMBER = dernier numero de build connu de "build_info"
#      (0 si package_ip_build_info.tcl n'a jamais ete lance sur ce poste)
###############################################################################

set script_dir [file normalize [file dirname [info script]]]
source [file join $script_dir "build_counter.tcl"]

proc set_build_info {cell_name {version_major 1} {version_minor 0} {build_number ""}} {

    set cell [get_bd_cells -quiet $cell_name]
    if {$cell eq ""} {
        puts "ERREUR : cellule '$cell_name' introuvable dans le Block Design ouvert."
        puts "Verifiez le nom d'instance (commande 'get_bd_cells' pour lister les cellules)."
        return -code error "cellule introuvable"
    }

    if {$build_number eq ""} {
        set build_number [current_build_number "build_info"]
    }

    set now      [clock seconds]
    set date_str [clock format $now -format "%Y%m%d"]
    set time_str [clock format $now -format "%H%M%S"]

    # date_str/time_str ne contiennent que des chiffres 0-9, valides tels
    # quels comme chiffres hexadecimaux : la valeur hexa du registre
    # reproduit donc directement la date/heure calendaire de facon lisible
    # (ex: 0x20260723 pour le 23 juillet 2026, pas une conversion numerique).
    set build_date_hex "0x${date_str}"
    set build_time_hex "0x00${time_str}"

    set version_major_hex [format "0x%08X" $version_major]
    set version_minor_hex [format "0x%08X" $version_minor]
    set build_number_hex  [format "0x%08X" $build_number]

    set_property -dict [list \
        CONFIG.G_BUILD_DATE    $build_date_hex \
        CONFIG.G_BUILD_TIME    $build_time_hex \
        CONFIG.G_VERSION_MAJOR $version_major_hex \
        CONFIG.G_VERSION_MINOR $version_minor_hex \
        CONFIG.G_BUILD_NUMBER  $build_number_hex \
    ] $cell

    puts "build_info_axi_v1_0 '$cell_name' mis a jour :"
    puts "  BUILD_DATE    = $build_date_hex (aaaammjj)"
    puts "  BUILD_TIME    = $build_time_hex (00hhmmss)"
    puts "  VERSION_MAJOR = $version_major_hex ($version_major)"
    puts "  VERSION_MINOR = $version_minor_hex ($version_minor)"
    puts "  BUILD_NUMBER  = $build_number_hex ($build_number)"
    puts "Verifiez que ce numero de build correspond a celui affiche par"
    puts "tcl/package_ip_build_info.tcl lors du dernier packaging de l'IP."
    puts "Pensez a regenerer les output products de l'IP (Generate Output Products),"
    puts "puis a (re)lancer synthese/implementation/bitstream pour que les nouvelles"
    puts "valeurs soient prises en compte."
}

# Execution directe si des arguments -tclargs ont ete fournis (mode batch),
# sinon le script se contente de definir la procedure ci-dessus pour un
# usage interactif depuis le Tcl Console.
if {[llength $argv] > 0} {
    set cell_name [lindex $argv 0]

    set version_major [lindex $argv 1]
    if {$version_major eq ""} {
        set version_major 1
    }

    set version_minor [lindex $argv 2]
    if {$version_minor eq ""} {
        set version_minor 0
    }

    set build_number [lindex $argv 3]

    set_build_info $cell_name $version_major $version_minor $build_number
}
