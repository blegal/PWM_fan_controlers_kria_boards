###############################################################################
# package_ip_build_info.tcl
#
# Package build_info_axi_v1_0 (interface AXI4-Lite, lecture seule : date/heure
# de synthese + version majeur/mineur) en IP Vivado reutilisable, dans un
# repertoire de repository IP local.
#
# Usage (depuis la racine du depot, ou n'importe ou) :
#   vivado -mode batch -source tcl/package_ip_build_info.tcl -tclargs [part] [repo_dir]
#
# Arguments optionnels :
#   part      : partie Vivado cible. Par defaut xck26-sfvc784-2LV-c (cf. note
#               dans package_ip_axi.tcl sur le part number KV260/KR260).
#   repo_dir  : repertoire de sortie du repository IP. Par defaut
#               ./ip_repo_build_info
#
# Les 5 generics (G_VERSION_MAJOR, G_VERSION_MINOR, G_BUILD_DATE, G_BUILD_TIME,
# G_BUILD_NUMBER) sont automatiquement exposees comme parametres de
# personnalisation de l'IP par ipx::create_xgui_files (pas de configuration
# xgui manuelle necessaire). Valeur par defaut = 0 pour les 5 : a renseigner
# par instance dans le Block Design, ou via tcl/set_build_info.tcl (calcule
# la date/heure courante, relit le numero de build courant -- cf.
# tcl/build_counter.tcl -- et positionne CONFIG.G_BUILD_DATE/G_BUILD_TIME/
# G_BUILD_NUMBER sur une instance deja placee).
#
# Ce script incremente lui-meme (via tcl/build_counter.tcl) un compteur de
# build persistant DEDIE AU PACKAGING de cette IP (composant "build_info"),
# affiche en fin de script et applique a la propriete Vivado "version" du
# composant packagee (visible dans l'IP catalog / Customize IP / Report IP
# Status) -- c'est un numero DIFFERENT du generic G_BUILD_NUMBER ci-dessus
# (qui, lui, doit etre positionne explicitement sur l'instance via
# tcl/set_build_info.tcl pour finir dans le bitstream et etre relu depuis le
# logiciel embarque). tcl/set_build_info.tcl reutilise par defaut ce meme
# compteur comme valeur de G_BUILD_NUMBER, ce qui permet en pratique de
# retrouver le meme numero aux 3 endroits (terminal de ce script, version
# Vivado du composant, registre BUILD_NUMBER lu par le logiciel).
#
# NOTE INFERENCE AXI : cf. note equivalente dans package_ip_axi.tcl (meme
# mecanisme d'inference best-effort, a finaliser a la main dans l'assistant
# Vivado si necessaire sur votre version).
###############################################################################

set part     [lindex $argv 0]
if {$part eq ""} {
    set part "xck26-sfvc784-2LV-c"
}

set repo_dir [lindex $argv 1]
if {$repo_dir eq ""} {
    set repo_dir "./ip_repo_build_info"
}

set script_dir [file normalize [file dirname [info script]]]
set src_dir     [file normalize "$script_dir/../src"]
set build_dir   "./_pkg_build_build_info"

source [file join $script_dir "build_counter.tcl"]

# Nettoyage d'un build precedent pour repartir propre
if {[file exists $build_dir]} {
    file delete -force $build_dir
}

create_project pkg_build_info_axi $build_dir -part $part -force

add_files -norecurse [list \
    "$src_dir/build_info_axi_v1_0.vhd" \
]

set_property top build_info_axi_v1_0 [current_fileset]
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

set build_number [next_build_number "build_info"]
set ip_version "1.$build_number"

set_property name             build_info_axi_v1_0                           $core
set_property display_name     "Build Info AXI"                              $core
set_property description      "Registres AXI4-Lite en lecture seule exposant la date/heure de synthese et la version (majeur/mineur) du design." $core
set_property vendor_display_name "user.org"                                 $core
set_property version          $ip_version                                  $core

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
puts " Build #$build_number -- IP build_info_axi_v1_0 packagee (version Vivado du composant = $ip_version)"
puts "=================================================================="
puts ""
puts "IP build_info_axi packagee dans : [file normalize $repo_dir]"
puts "Pensez a l'ajouter au repository IP de votre projet :"
puts "  set_property ip_repo_paths {[file normalize $repo_dir]} \[current_project\]"
puts {  update_ip_catalog}
puts ""
puts "Pour verifier apres synthese/bitstream que la carte tourne bien avec CE"
puts "packaging (Build #$build_number), comparez avec la valeur relue par le"
puts "logiciel embarque (BuildInfo_GetBuildNumber) et avec la version affichee"
puts "dans Vivado (IP catalog / Customize IP / Report IP Status) : $ip_version."
puts ""
puts "Pensez egalement a renseigner G_BUILD_DATE/G_BUILD_TIME/G_VERSION_MAJOR/"
puts "G_VERSION_MINOR/G_BUILD_NUMBER sur chaque instance (defaut = 0) -- cf."
puts "tcl/set_build_info.tcl (reutilise par defaut ce meme Build #$build_number)."
