#!/bin/bash

set -e

export src="https://cdn.gea.esac.esa.int/Gaia"
export dst="/media/Matrix/Data/ESA/Gaia"
export conn=100
export bandwidth=110

export ROUTE='10.0.0.$([ $(expr $RANDOM % "$(expr 20 + 10 - 2)") -lt "$(expr 20 - 1)" ] && echo 11 || echo 12)'

export meta=$(mktemp -d)
echo "Use \"$meta\" for metadata."

echo '/' > "$meta/dirs.txt"
truncate -s0 "$meta/files.txt"

while [ $(cat "$meta/dirs.txt" | wc -l) -gt 0 ]; do
    rm -rf "$meta/"{children,dirs,files}".d"
    mkdir -p "$meta/"{children,dirs,files}".d"

    parallel -j"$conn" --line-buffer --bar 'bash -c '"'"'
        set -e
        meta="'"$meta"'"
        esc="$(sed "s/\([\/\.]\)/\\\\\1/g" <<< "{}")"
        curl -sSL --interface '$ROUTE' "'"$src"'{}" | sed -n "s/.*[[:space:]]href[[:space:]]*=[[:space:]]*\"\([^\.\"][^\"]*\).*/\1/p" | sed "s/^/$esc/" >> "$meta/children.d/{%}.txt"
    '"'" :::: "$meta/dirs.txt"

    parallel -j"$(nproc)" --line-buffer --bar 'bash -c '"'"'
        set -e
        meta="'"$meta"'"
        cat "{}" | sed -n "/[^\/]$/p" >> "$meta/files.d/{%}.txt"
        cat "{}" | sed -n "/[\/]$/p" >> "$meta/dirs.d/{%}.txt"
    '"'" ::: $(ls "$meta/children.d/"*.txt)

    rm -f "$meta/dirs.txt"
    parallel -j0 --line-buffer --bar 'bash -c '"'"'
        set -e
        meta="'"$meta"'"
        cat "$meta/{}.d/"*.txt >> "$meta/{}.txt"
        rm -rf "$meta/{}.d"
    '"'" ::: dirs files
done

rm -rf "$meta/"{children,dirs,files}".d" "$meta/"{children,dirs}".txt"
echo "File list is ready in \"$meta/files.txt\"."

time parallel -j"$conn" --line-buffer --bar --shuf 'bash -c '"'"'
    set -e
    conn="'"$conn"'"
    bandwidth="'"$bandwidth"'"
    load="$bandwidth"
    while :; do
        delay="$(bc -l <<< "$(expr $RANDOM % 900) / 1000 + 0.1")"
        beg=$(cat /proc/net/dev | grep enp | sed "s/[[:space:]][[:space:]]*/ /g" | cut -f2 -d" " | paste -sd+ | bc)
        sleep "$delay"
        end=$(cat /proc/net/dev | grep enp | sed "s/[[:space:]][[:space:]]*/ /g" | cut -f2 -d" " | paste -sd+ | bc)
        load=$(bc -l <<< "($end - $beg) / $delay / 131072")
        [ $(bc <<< "$load >= $bandwidth * ($conn - 1) / $conn") -eq 0 ] && break
        echo "Throttle (load: $(sed "s/\..*//" <<< "$load") Mbps)"
    done
    mkdir -p "$(dirname "'"$dst"'/{}")"
    cd $_
    wget -cq --bind-address='$ROUTE' --limit-rate=$(bc <<< "($bandwidth - $load) * 1.1 * 131072" | sed "s/\..*//") "'"$src"'{}"
'"'" :::: "$meta/files.txt"

rm -rf "$meta"
