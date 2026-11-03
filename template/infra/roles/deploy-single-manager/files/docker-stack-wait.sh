#!/bin/bash

set -o nounset -o errexit -o errtrace -o pipefail
shopt -s inherit_errexit dotglob
IFS=$'\n\t'
trap $'echo >&2 "Error: exited with status $? at line $LINENO in $0"; awk \'NR>L-4 && NR<L+4 { printf "%3d %3s %s\\n",NR,(NR==L?">>>":""),$0 }\' L=$LINENO $0' ERR

trap "{ exit 1; }" TERM INT
opt_h=0
opt_r=0
opt_s=5
opt_t=60
opt_n=
opt_f=
start_epoc="$(date +%s)"

usage() {
    echo "$(basename "$0") [opts] stack_name"
    echo "  -f filter: only wait for services matching filter, may be passed multiple"
    echo "             times, see docker stack services for the filter syntax"
    echo "  -h:        this help message"
    echo "  -n name:   only wait for specific service names, overrides any filters,"
    echo "             may be passed multiple times, do not include the stack name prefix"
    echo "  -r:        treat a rollback as successful"
    echo "  -s sec:    frequency to poll service state (default $opt_s sec)"
    echo "  -t sec:    timeout to stop waiting"
    [[ $opt_h == 1 ]] && exit 0 || exit 1
}
check_timeout() {
    if [[ $opt_t -gt 0 ]]; then
        cur_epoc="$(date +%s)"
        cutoff_epoc="$((start_epoc + opt_t - opt_s))"
        if [[ $cur_epoc -gt $cutoff_epoc ]]; then
            echo "=== Error: Timeout $opt_t s exceeded"
            print_service_logs "$last_failed_service"
            exit 1
        fi
    fi
}
get_service_ids() {
    if [[ -n $opt_n ]]; then
        service_list=""
        for name in $opt_n; do
            service_list="${service_list:+${service_list} }${stack_name}_${name}"
        done
        docker service inspect --format '{{.ID}}' "$service_list"
    else
        docker stack services ${opt_f:+"opt_f"} -q "$stack_name"
    fi
}

declare -A service_states_cache
service_state() {
    local service="$1"
    local state="$2"
    local service_done="$3"
    case $service_done in
        0) service_done_text="[waiting]" ;;
        1) service_done_text="[success]" ;;
        2) service_done_text="[ERROR]" ;;
        *) service_done_text="[unknown]" ;;
    esac

    if [[ "${service_states_cache["$service"]-}" != "$state" ]]; then
        echo "$(date '+%F %T%z') - Service $service: $service_done_text $state"
        service_states_cache["$service"]="$state"
    fi
}

get_service_timestamp() {
    local service=$1
    local format=$2
    docker service inspect --format "$format" "$service" |
        awk -F. '{print $1 " UTC"}'
}
print_service_logs() {
    local service=$1
    [[ -z $service ]] && return

    local failed_tasks failed_tasks_id failed_tasks_error
    failed_tasks="$(docker service ps --format 'table {{.ID}} {{.Name}} {{.Error}}' "$service" | tail -n+2 | grep-c1 -v -A1 ' \\_ ' | grep-c1 ' "')"
    [[ -z $failed_tasks ]] && return

    failed_tasks_id="$(echo "$failed_tasks" | grep-c1 -oP '^[^ ]+')"
    failed_tasks_error="$(echo "$failed_tasks" | grep-c1 -oP '(?<=").*(?=")')"

    echo "=== Task errors (service $service)"
    echo "$failed_tasks_error"
    for task in ${failed_tasks_id}; do
        echo "=== Task logs (task $task)"
        docker service logs --timestamps --no-trunc "$task" 2>&1
    done
}

grep-c1() { grep "$@" || test $? = 1; }

while getopts 'f:hn:rs:t:' opt; do
    case $opt in
        f) opt_f="${opt_f:+${opt_f} }-f $OPTARG" ;;
        h) opt_h=1 ;;
        n) opt_n="${opt_n:+${opt_n} } $OPTARG" ;;
        r) opt_r=1 ;;
        s) opt_s="$OPTARG" ;;
        t) opt_t="$OPTARG" ;;
        *) ;;
    esac
done
shift "$((OPTIND - 1))"

if [[ $# != 1 || $opt_h == 1 || $opt_s -lt 1 ]]; then
    usage
fi

stack_name=$1

stack_done=0
last_failed_service=""
while [[ $stack_done == 0 ]]; do
    stack_done=1
    service_ids="$(get_service_ids)"
    if [[ -z $service_ids ]]; then
        echo "Error: no services found" >&2
        exit 1
    fi
    for service_id in ${service_ids}; do
        service_done=0
        service="$(docker service inspect --format '{{.Spec.Name}}' "$service_id")"

        updatedAt="$(get_service_timestamp "$service_id" '{{.UpdatedAt}}')"

        update_state="$(docker service inspect -f '{{if .UpdateStatus}}{{.UpdateStatus.State}}{{else}}new{{end}}' "$service_id")"
        update_state_message="$(docker service inspect -f '{{if .UpdateStatus}}{{.UpdateStatus.Message}}{{else}}new{{end}}' "$service_id")"
        state_details="$update_state_message"

        case "$update_state" in
        paused)
            service_done=0
            ;;
        rollback_paused)
            service_done=2
            ;;
        rollback_*)
            if [[ $opt_r = 0 ]]; then
                service_done=2
            fi
            ;;
        completed)
            service_done=1
            ;;
        esac

        if [[ $service_done == 1 ]]; then
            completedAt="$(get_service_timestamp "$service_id" '{{.UpdateStatus.CompletedAt}}')"
            dateDiff="$(($(date -ud "${updatedAt}" +%s) - $(date -ud "${completedAt}" +%s)))"
            if [[ ${dateDiff/#-/} -gt 1 ]]; then
                service_done=0
                state_details="$update_state_message at $completedAt != $updatedAt, waiting"
            fi
        fi

        service_is_job="\(([0-9]+)/([0-9]+) completed\)$"
        service_is_usual="^([0-9]+)/([0-9]+)"
        replicas="$(docker service ls --format '{{.Replicas}}' --filter "id=$service_id")"
        if [[ ! $replicas =~ $service_is_job ]]; then
            if [[ ! $replicas =~ $service_is_usual ]]; then
                echo "Error: unexpected $replicas"
                exit 1
            fi
        fi
        replicas_current="${BASH_REMATCH[1]}"
        replicas_target="${BASH_REMATCH[2]}"

        task_desired_state="$(docker service ps --format '{{.DesiredState}}' "$service_id" | head -n 1)"
        task_current_state_full="$(docker service ps --format '{{.CurrentState}}' "$service_id" | head -n 1)"
        task_current_state=${task_current_state_full%% *}

        restart_condition="$(docker service inspect --format '{{.Spec.TaskTemplate.RestartPolicy.Condition}}' "$service_id")"

        if [[ ($service_done == 0 && $update_state == new) ||
            ($service_done == 0 && $update_state == paused) ||
            ($service_done == 1 && $replicas_current != "$replicas_target") ||
            ($service_done == 1 && $update_state == completed && $replicas_current == "$replicas_target" &&
            $task_desired_state == Running && $task_current_state == Running && $restart_condition == none) ]]; then

            task_desired_states_count="$(docker service ps --format 'table {{.Name}} {{.DesiredState}}' "$service_id" | tail -n +2 | grep-c1 -v ' \\_ ' | awk '{print $2}' | sort | uniq | wc -l)"
            task_current_states_count="$(docker service ps --format 'table {{.Name}} {{.CurrentState}}' "$service_id" | tail -n +2 | grep-c1 -v ' \\_ ' | awk '{print $2}' | sort | uniq | wc -l)"
            task_errors="$(docker service ps --format 'table {{.Name}} {{.Error}}' "$service_id" | grep-c1 -v ' \\_ ' | grep-c1 -oP '(?<=").*(?=")')"

            state_details="task desired state: $task_desired_state, task current state: $task_current_state${task_errors:+, task errors: $task_errors}"

            if [[ $update_state == paused ]]; then
                if [[ $restart_condition == none && $task_desired_state == Shutdown && $task_current_state == Complete &&
                    $task_desired_states_count == 1 && $task_current_states_count == 1 && -z "${task_errors:-}" ]]; then
                    service_done=1
                    state_details="job is done"
                else
                    service_done=2
                    state_details="$update_state_message"
                fi
            elif [[ $task_desired_state == Shutdown && $task_current_state == Complete &&
                $task_desired_states_count == 1 && $task_current_states_count == 1 && $task_errors == "" ]]; then
                service_done=1
                state_details="job is done"
            elif [[ $task_desired_state == Shutdown && $task_current_state == Failed &&
                $task_desired_states_count == 1 && $task_current_states_count == 1 ]]; then
                service_done=2
            elif [[ $replicas_current == "$replicas_target" && $task_desired_state == "$task_current_state" &&
                $task_desired_states_count == 1 && $task_current_states_count == 1 && $task_errors == "" ]]; then
                if [[ $restart_condition == none ]]; then
                    cur_epoc="$(date +%s)"
                    cutoff_epoc="$((start_epoc + opt_t - opt_s))"
                    if [[ $cur_epoc -gt $cutoff_epoc ]]; then
                        state_details="job is still running, don't waiting any more"
                        service_done=1
                    else
                        state_details="job is running"
                        service_done=0
                    fi
                else
                    service_done=1
                    state_details="replicated $replicas, task state: $task_current_state"
                fi
            else
                service_done=0
                state_details="replicating $replicas, task state: $task_current_state (desired: $task_desired_state)"
                last_failed_service="$service_id"
            fi
        fi

        service_state "$service" "$state_details" "$service_done"

        if [[ $service_done == 2 ]]; then
            stack_done=2
            last_failed_service="$service_id"
            echo "=== Error: This deployment will not complete"
            print_service_logs "$last_failed_service"
            exit 1
        elif [[ $service_done == 0 ]]; then
            stack_done=0
        fi
    done
    if [[ $stack_done == 0 ]]; then
        check_timeout
        sleep "${opt_s}"
    elif [[ $stack_done == 1 ]]; then
        echo "=== Deploy is successful"
        exit 0
    fi
done
