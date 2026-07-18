#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../scripts/wait-for-rollout.sh"
}

@test "affiche l'aide avec --help" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "echoue si --name n'est pas fourni" {
    run "$SCRIPT" --namespace default
    [ "$status" -eq 1 ]
    [[ "$output" == *"--name est obligatoire"* ]]
}

@test "refuse un type de ressource invalide" {
    run "$SCRIPT" --name foo --type pod
    [ "$status" -eq 1 ]
    [[ "$output" == *"Type de ressource invalide"* ]]
}

@test "echoue proprement sur une option inconnue" {
    run "$SCRIPT" --bad-option
    [ "$status" -eq 1 ]
    [[ "$output" == *"Option inconnue"* ]]
}
