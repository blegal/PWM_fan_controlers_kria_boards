###############################################################################
# build_counter.tcl
#
# Compteur de build persistant partage par les scripts tcl/package_ip_*.tcl.
# Un fichier plat par composant (repertoire tcl/.build_counters/, cree au
# besoin) stocke un entier, incremente de 1 a chaque appel de
# next_build_number. Permet de tracer/verifier qu'un packaging donne
# correspond bien a ce qui est ensuite visible dans Vivado (propriete
# "version" du composant package) et, pour build_info_axi_v1_0, sur la
# cible elle-meme (registre BUILD_NUMBER, cf. tcl/set_build_info.tcl).
#
# Ce compteur est un etat LOCAL de build (comme _pkg_build_*/ ou ip_repo_*/),
# pas une source versionnee : tcl/.build_counters/ est dans .gitignore.
# Chaque poste de travail/checkout a donc sa propre numerotation -- l'objectif
# est de vous permettre de verifier, sur VOTRE poste, qu'un packaging+synthese
# donnes correspondent bien entre eux (terminal / Vivado / cible), pas de
# fournir un numero de build globalement unique multi-machines.
###############################################################################

# Capture au moment du "source" de CE fichier (pas au moment de l'appel des
# procs ci-dessous) : [info script] reflete le fichier sourced le plus
# imbrique au moment de l'evaluation, donc l'interroger depuis l'interieur
# d'un corps de proc renverrait le chemin du SCRIPT APPELANT (package_ip_*.tcl)
# et non celui de build_counter.tcl si on le faisait paresseusement.
set ::build_counter_script_dir [file normalize [file dirname [info script]]]

proc build_counter_dir {} {
    return [file join $::build_counter_script_dir ".build_counters"]
}

# Incremente et retourne le nouveau numero de build pour le composant $name
# (ex: "axi", "standalone", "open_loop", "build_info").
proc next_build_number {name} {
    set dir [build_counter_dir]
    file mkdir $dir
    set path [file join $dir "$name.count"]

    set n 0
    if {[file exists $path]} {
        set fh [open $path r]
        set n [string trim [read $fh]]
        close $fh
        if {![string is integer -strict $n]} {
            set n 0
        }
    }
    incr n

    set fh [open $path w]
    puts $fh $n
    close $fh

    return $n
}

# Relit (SANS incrementer) le dernier numero de build connu pour $name.
# Retourne 0 si aucun compteur n'existe encore (aucun packaging effectue).
proc current_build_number {name} {
    set path [file join [build_counter_dir] "$name.count"]
    if {![file exists $path]} {
        return 0
    }
    set fh [open $path r]
    set n [string trim [read $fh]]
    close $fh
    if {![string is integer -strict $n]} {
        return 0
    }
    return $n
}
