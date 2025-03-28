#!/bin/bash

delete_resources() {
    local resource_type=$1
    local pattern=$2

    echo -e "\nElenca tutte le $resource_type che iniziano con $pattern"

    local ids
    ids=$(openstack "${resource_type}" list --format value --column ID --column Name \
        | awk -v pat="${pattern}" '$2 ~ pat {print $1}')

    if [ -z "$ids" ]; then
        echo "Nessuna $resource_type trovata che inizia con '$pattern'."
        return
    fi

    local total=$(echo "$ids" | wc -l)
    local temp_file=$(mktemp)  # File temporaneo per il conteggio
    echo 0 > "$temp_file"

    echo "Trovate $total $resource_type da cancellare."

    # Funzione per disegnare la barra di progresso
    draw_progress_bar() {
        local width=50  # Larghezza della barra
        local count=$(cat "$temp_file")
        local progress=$((count * width / total))
        local bar=""
        local i

        for ((i=0; i<progress; i++)); do
            bar+="="
        done

        for ((i=progress; i<width; i++)); do
            bar+=" "
        done

        printf "\r[%s] %3d%%" "$bar" "$((count * 100 / total))"
    }

    # Funzione per cancellare una singola risorsa e aggiornare la barra
    delete_single() {
        local id=$1
        openstack "${resource_type}" delete "$id" >/dev/null 2>&1

        # Aggiorna il conteggio in modo sicuro
        (
            flock -x 200  # Lock per evitare race conditions
            count=$(cat "$temp_file")
            ((count++))
            echo "$count" > "$temp_file"
        ) 200>"$temp_file.lock"

        draw_progress_bar
    }

    export -f delete_single
    export -f draw_progress_bar
    export resource_type
    export temp_file
    export total

    echo "$ids" | xargs -I{} -P 4 bash -c 'delete_single "$@"' _ {}

    echo -e "\nTutte le $resource_type che iniziano con '$pattern' sono state cancellate."

    rm -f "$temp_file" "$temp_file.lock"  # Pulisce i file temporanei
}

# Elimina porte in parallelo (max 4 processi)
delete_resources "port" "s_rally_"

# Elimina network in parallelo (max 4 processi)
delete_resources "network" "s_rally_"

