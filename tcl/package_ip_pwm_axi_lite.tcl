###############################################################################
# package_ip_pwm_axi_lite.tcl
#
# Package pwm_axi_lite_v1_0 (generateur PWM configurable via 3 registres
# AXI4-Lite : PERIOD, THRESHOLD, CTRL -- actif par defaut au reset) en IP
# Vivado reutilisable, dans un repertoire de repository IP local.
#
# Usage (depuis la racine du depot, ou n'importe ou) :
#   vivado -mode batch -source tcl/package_ip_pwm_axi_lite.tcl -tclargs [part] [repo_dir]
#
# Arguments optionnels :
#   part      : partie Vivado cible. Par defaut xck26-sfvc784-2LV-c (cf. note
#               dans package_ip_axi.tcl sur le part number KV260/KR260).
#   repo_dir  : repertoire de sortie du repository IP. Par defaut
#               ./ip_repo_pwm_axi_lite
#
# NOTE INFERENCE AXI : cf. note equivalente dans package_ip_axi.tcl (meme
# mecanisme d'inference best-effort, a finaliser a la main dans l'assistant
# Vivado si necessaire sur votre version).
#
# Comme les autres scripts package_ip_*.tcl de ce depot, un compteur de
# build persistant (tcl/build_counter.tcl) est incremente a chaque
# execution, affiche dans le terminal (Build #N), et applique a la
# propriete Vivado "version" du composant packagee (1.N).
###############################################################################

set part     [lindex $argv 0]
if {$part eq ""} {
    set part "xck26-sfvc784-2LV-c"
}

set repo_dir [lindex $argv 1]
if {$repo_dir eq ""} {
    set repo_dir "./ip_repo_pwm_axi_lite"
}

set script_dir [file normalize [file dirname [info script]]]
set src_dir     [file normalize "$script_dir/../src"]
set build_dir   "./_pkg_build_pwm_axi_lite"

source [file join $script_dir "build_counter.tcl"]

# Nettoyage d'un build precedent pour repartir propre
if {[file exists $build_dir]} {
    file delete -force $build_dir
}

create_project pkg_pwm_axi_lite $build_dir -part $part -force

add_files -norecurse [list \
    "$src_dir/pwm_axi_lite_v1_0.vhd" \
]

set_property top pwm_axi_lite_v1_0 [current_fileset]
update_compile_order -fileset sources_1

# Nettoyage d'un repo_dir precedent : ipx::package_project reutilise/fusionne
# un component.xml existant a cet emplacement plutot que d'en repartir a
# zero (cf. note detaillee dans package_ip_axi.tcl).
if {[file exists $repo_dir]} {
    file delete -force $repo_dir
}

file mkdir $repo_dir

ipx::package_project -root_dir $repo_dir -vendor user.org -library user \
    -taxonomy /UserIP -import_files -force

set core [ipx::current_core]

set build_number [next_build_number "pwm_axi_lite"]
set ip_version "1.$build_number"

set_property name             pwm_axi_lite_v1_0                             $core
set_property display_name     "PWM AXI Lite"                                $core
set_property description      "Generateur de signal PWM configurable via 3 registres AXI4-Lite : PERIOD (coups d'horloge par periode), THRESHOLD (coup a partir duquel la sortie passe a l'etat bas), CTRL (bit0=ENABLE, actif par defaut, 70% de temps haut)." $core
set_property vendor_display_name "user.org"                                 $core
set_property version          $ip_version                                  $core

# Inference automatique de l'interface AXI4-Lite -- UN SEUL appel, qui
# detecte et associe deja lui-meme s_axi_aclk/s_axi_aresetn (cf. note
# detaillee dans package_ip_axi.tcl sur [BD 41-1732] si des appels
# supplementaires etaient ajoutes ici).
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
puts " Build #$build_number -- IP pwm_axi_lite_v1_0 packagee (version Vivado du composant = $ip_version)"
puts "=================================================================="
puts ""
puts "IP pwm_axi_lite packagee dans : [file normalize $repo_dir]"
puts "Pensez a l'ajouter au repository IP de votre projet :"
puts "  set_property ip_repo_paths {[file normalize $repo_dir]} \[current_project\]"
puts {  update_ip_catalog}
puts ""
puts "Pour verifier apres synthese/bitstream que la carte tourne bien avec CE"
puts "packaging (Build #$build_number), comparez avec la version affichee dans"
puts "Vivado (IP catalog / Customize IP / Report IP Status) : $ip_version."
