#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../scripts/cluster_health.sh"
}

@test "affiche l'aide avec --help" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "échoue proprement sur une option inconnue" {
    run "$SCRIPT" --bad-option
    [ "$status" -eq 1 ]
    [[ "$output" == *"Option inconnue"* ]]
}

@test "refuse de combiner --context et --all-contexts" {
    run "$SCRIPT" --context foo --all-contexts
    [ "$status" -eq 1 ]
    [[ "$output" == *"Impossible de combiner"* ]]
}

@test "accepte --json avec --help sans erreur" {
    run "$SCRIPT" --json --help
    [ "$status" -eq 0 ]
}
