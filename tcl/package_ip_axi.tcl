###############################################################################
# package_ip_axi.tcl
#
# Package pwm_fan_thermal_axi_v1_0 (interface AXI4-Lite) en IP Vivado
# reutilisable, dans un repertoire de repository IP local.
#
# Usage (depuis la racine du depot, ou n'importe ou) :
#   vivado -mode batch -source tcl/package_ip_axi.tcl -tclargs [part] [repo_dir]
#
# Arguments optionnels :
#   part      : partie Vivado cible. Par defaut xck26-sfvc784-2LV-c (partie
#               reelle du SOM Kria K26 utilise sur la KV260 -- PAS le
#               XCZU5EV generique, cf. note ci-dessous). A adapter si vous
#               ciblez un projet "board part" plutot qu'un projet "part".
#   repo_dir  : repertoire de sortie du repository IP. Par defaut ./ip_repo_axi
#
# NOTE PART NUMBER : la KV260 embarque un XCK26-SFVC784-2LV-C, un "cousin"
# du XCZU5EV generique mais avec un brochage/des IO differents (cf. binding
# custom du SOM K26). Si votre projet Vivado utilise le board file Kria K26
# (xilinx.com:kv260_som:...), preferez creer ce depot IP a l'interieur d'un
# projet deja cree sur ce board file plutot que d'utiliser -part ici, pour
# eviter tout mismatch de partie lors de l'ajout ulterieur de l'IP au design.
#
# NOTE INFERENCE AXI : ce script tente une inference automatique de
# l'interface AXI4-Lite via un seul appel a ipx::infer_bus_interface, en se
# basant sur le nommage standard des ports (s_axi_*) -- CET APPEL UNIQUE
# DETECTE ET ASSOCIE DEJA s_axi_aclk/s_axi_aresetn comme horloge/reset du bus
# (Vivado le fait automatiquement par correspondance de prefixe de nom). Ne
# PAS ajouter d'appels supplementaires ipx::infer_bus_interface sur
# s_axi_aclk/s_axi_aresetn ni ipx::associate_bus_interfaces : une version
# anterieure de ce script les ajoutait "par securite", ce qui creait en
# realite une DEUXIEME association du meme pin d'horloge sur S_AXI et
# provoquait [BD 41-1732] "found to be associated with multiple clock-pins"
# a la validation du Block Design (cf. commentaire au point d'appel plus bas).
#
# La syntaxe exacte de ipx::infer_bus_interface a pu varier legerement entre
# versions de Vivado. Si l'inference echoue ou si l'onglet "Interfaces" de
# l'IP ne montre pas correctement l'interface S_AXI apres generation, ouvrez
# l'IP dans l'assistant Vivado (Tools -> Create and Package New IP -> Package
# a specification -> pointer vers le repo_dir genere) et finalisez l'onglet
# Interfaces manuellement une fois (Vivado detecte alors tres bien s_axi_*
# par nommage), puis re-sauvegardez ; le Tcl Console de Vivado affichera
# alors les commandes exactes executees, a reporter ici pour rendre le
# script 100% reproductible sur votre version.
###############################################################################

set part     [lindex $argv 0]
if {$part eq ""} {
    set part "xck26-sfvc784-2LV-c"
}

set repo_dir [lindex $argv 1]
if {$repo_dir eq ""} {
    set repo_dir "./ip_repo_axi"
}

set script_dir [file normalize [file dirname [info script]]]
set src_dir     [file normalize "$script_dir/../src"]
set build_dir   "./_pkg_build_axi"

source [file join $script_dir "build_counter.tcl"]

# Nettoyage d'un build precedent pour repartir propre
if {[file exists $build_dir]} {
    file delete -force $build_dir
}

create_project pkg_pwm_fan_thermal_axi $build_dir -part $part -force

add_files -norecurse [list \
    "$src_dir/sysmon_temp_acq.vhd" \
    "$src_dir/fan_thermal_ctrl.vhd" \
    "$src_dir/pwm_fan_thermal_axi_v1_0.vhd" \
]

set_property top pwm_fan_thermal_axi_v1_0 [current_fileset]
update_compile_order -fileset sources_1

# Nettoyage d'un repo_dir precedent : indispensable, pas juste cosmetique.
# ipx::package_project reutilise/fusionne un component.xml existant a cet
# emplacement plutot que d'en repartir a zero ; sans ce nettoyage, relancer
# ce script (apres une modification du VHDL par exemple) fait s'accumuler
# les associations d'horloge ajoutees par ipx::associate_bus_interfaces
# plus bas, provoquant [BD 41-1732] "associated with multiple clock-pins"
# (le meme pin s_axi_aclk liste plusieurs fois) a l'ouverture du Block
# Design. Si vous avez deja genere ce repo_dir avant ce correctif, supprimez
# -le a la main une fois (ou relancez simplement ce script, qui s'en charge
# desormais).
if {[file exists $repo_dir]} {
    file delete -force $repo_dir
}

file mkdir $repo_dir

ipx::package_project -root_dir $repo_dir -vendor user.org -library user \
    -taxonomy /UserIP -import_files -force

set core [ipx::current_core]

set build_number [next_build_number "axi"]
set ip_version "1.$build_number"

set_property name             pwm_fan_thermal_axi_v1_0                      $core
set_property display_name     "PWM Fan Thermal AXI"                          $core
set_property description      "Controleur PWM ventilateur KV260 avec acquisition temperature SYSMON et asservissement thermique, interface AXI4-Lite (registres CTRL/PERIOD/DUTY/TEMP/seuils)." $core
set_property vendor_display_name "user.org"                                  $core
set_property version          $ip_version                                   $core

# Inference automatique de l'interface AXI4-Lite. ipx::infer_bus_interface,
# lorsqu'il recoit la liste complete des ports d'un bundle aximm_rtl nomme
# selon la convention standard (prefixe s_axi_), detecte ET ASSOCIE DEJA
# LUI-MEME s_axi_aclk/s_axi_aresetn comme horloge/reset de ce bus (Vivado
# scanne les ports "s_axi_aclk"/"s_axi_aresetn" par correspondance de
# prefixe). Des appels supplementaires explicites a ipx::infer_bus_interface
# sur s_axi_aclk (type clock_rtl) et a ipx::associate_bus_interfaces
# provoquaient donc une DEUXIEME association du meme pin d'horloge sur le
# meme bus S_AXI -> [BD 41-1732] "found to be associated with multiple
# clock-pins" (le meme s_axi_aclk liste deux fois) a la validation du Block
# Design, de facon deterministe des le premier packaging (pas seulement en
# cas de re-packaging sur un repo_dir non nettoye). Ne pas les reajouter :
# un seul appel suffit et couvre deja l'horloge/le reset.
catch {
    ipx::infer_bus_interface {
        s_axi_awaddr s_axi_awvalid s_axi_awready
        s_axi_wdata  s_axi_wvalid  s_axi_wready
        s_axi_bresp  s_axi_bvalid  s_axi_bready
        s_axi_araddr s_axi_arvalid s_axi_arready
        s_axi_rdata  s_axi_rresp   s_axi_rvalid  s_axi_rready
    } xilinx.com:interface:aximm_rtl:1.0 $core
}

ipx::create_xgui_files      $core
ipx::update_checksums       $core
ipx::save_core              $core

close_project

puts ""
puts "=================================================================="
puts " Build #$build_number -- IP pwm_fan_thermal_axi_v1_0 packagee (version Vivado du composant = $ip_version)"
puts "=================================================================="
puts ""
puts "IP AXI packagee dans : [file normalize $repo_dir]"
puts "Pensez a l'ajouter au repository IP de votre projet :"
puts "  set_property ip_repo_paths {[file normalize $repo_dir]} \[current_project\]"
puts {  update_ip_catalog}
puts ""
puts "Pour verifier apres synthese/bitstream que la carte tourne bien avec CE"
puts "packaging (Build #$build_number), comparez avec la version affichee dans"
puts "Vivado (IP catalog / Customize IP / Report IP Status) : $ip_version."
