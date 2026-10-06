#!/usr/bin/env bash
# Convert CTS atlases into a fixed set of named classes, using IMOD programs only.
#
# Atlas_<suffix>.mrc stores value v for the label on line v+1 of Atlas_<suffix>.txt (line 1 is
# "background"). The numbering changes from run to run, so classes are matched by atlas NAME.
# Every run gets the same class ids:
#   0 background, 1 microtubule, 2 actin, 3 cofilactin, 4 ribosome, 5 membrane
# Atlas labels not listed in CLASS_ATLAS are written as background.
#
# Outputs, in <run>/labels/ (or <outroot>/<run>/ with --out):
#   labels.mrc            unsigned bytes 0..5, same size/pixel size as the atlas and 5_recon
#   mask_<class>.mrc      0/1 per class (all zero when the class is absent from the run)
#   labels.json           class id -> name, atlas names/values, voxel counts, colors, csv points
#   particles.mod         IMOD scattered-point model from zcoords_<label>.csv, object k = class k
#
# Usage:
#   cts_atlas_to_labels.sh [--force] [--no-masks] [--no-model] [--out DIR] PATH [PATH ...]
#   PATH is a run folder (contains sim/Atlas_sim.txt) or a folder of run folders.
# Example:
#   scripts/cts_atlas_to_labels.sh /mnt/big_data/CTS_actin_cofilactin_MT_simulation
#
# Requires IMOD (clip, header, point2model). Same outputs as scripts/cts_atlas_to_labels.m.
# See Markdowns/atlas_labels_actin_cofilactin_mt.md for what the atlas labels mean.

set -euo pipefail

## Class definitions (class id = position in the arrays, starting at 1)
CLASS_NAMES=(microtubule actin cofilactin ribosome membrane)
# atlas names merged into each class, space separated (e.g. "cytosol assembly")
CLASS_ATLAS=("neuroMT" "actin_long" "cofilactin_long" "ribo_4ujd" "vesicle")
CLASS_COLORS=("0 158 115" "230 159 0" "213 94 0" "0 114 178" "204 121 167")
# sphere radius in A for displaying csv points in 3dmod (membrane has no csv)
CLASS_RADIUS_A=(125 40 50 130 0)

## Options
force=0; masks=1; model=1; outroot=""; inputs=()
while [ $# -gt 0 ]; do
    case "$1" in
        --force) force=1 ;;
        --no-masks) masks=0 ;;
        --no-model) model=0 ;;
        --out) outroot="$2"; shift ;;
        -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
        *) inputs+=("$1") ;;
    esac
    shift
done
[ ${#inputs[@]} -gt 0 ] || { sed -n '2,24p' "$0"; exit 1; }
for prog in clip header point2model; do
    command -v "$prog" >/dev/null || { echo "IMOD program not found: $prog" >&2; exit 1; }
done
export WRITE_MODE0_SIGNED=0 # plain unsigned bytes, IMOD 5 otherwise stores bytes shifted by -128

## Collect run folders
runs=()
for p in "${inputs[@]}"; do
    p="${p%/}"
    if [ -f "$p/sim/Atlas_sim.txt" ] || [ -f "$p/zero_dose_pair/Atlas_zero_dose_pair.txt" ]; then
        runs+=("$p")
    else
        for r in "$p"/*/; do
            r="${r%/}"
            if [ -f "$r/sim/Atlas_sim.txt" ] || [ -f "$r/zero_dose_pair/Atlas_zero_dose_pair.txt" ]; then
                runs+=("$r")
            fi
        done
    fi
done
[ ${#runs[@]} -gt 0 ] || { echo "No CTS run folders with an atlas found" >&2; exit 1; }

## Per-run conversion
convert_run() {
    local run="$1" name sub suffix atlas txt ref out tmp pix nx ny nz k v
    name=$(basename "$run")
    if [ -f "$run/sim/Atlas_sim.txt" ]; then sub=sim; else sub=zero_dose_pair; fi
    suffix="$sub"
    atlas="$run/$sub/Atlas_$suffix.mrc"; txt="$run/$sub/Atlas_$suffix.txt"
    ref="$run/$sub/5_recon_$suffix.mrc"; [ -f "$ref" ] || ref="$atlas"
    if [ -n "$outroot" ]; then out="$outroot/$name"; else out="$run/labels"; fi

    if [ -f "$out/labels.json" ] && [ $force -eq 0 ]; then
        echo "$name: labels exist, skipping (use --force to redo)"; return
    fi
    mkdir -p "$out"
    tmp=$(mktemp -d "$out/.tmp.XXXXXX")
    trap 'rm -rf "$tmp"' RETURN

    pix=$(header -pixel "$atlas" | awk '{printf "%.4f", $1}')
    read -r nx ny nz < <(header -size "$atlas")

    # k*mask per class: voxels with atlas value v are kept by thresholding at v-0.5 and v+0.5
    local -a ncsv vals labs nvals
    local parts=() json_classes="" pts="$tmp/points.txt" maxobj=0 npts
    : > "$pts"
    for k in "${!CLASS_NAMES[@]}"; do
        local id=$((k+1)) cname="${CLASS_NAMES[$k]}" cvals="" clabs="" cparts=() nm line
        for nm in ${CLASS_ATLAS[$k]}; do
            line=$(grep -nxF -- "$nm" "$txt" | head -1 | cut -d: -f1 || true)
            [ -n "$line" ] || continue
            v=$((line-1))
            clip threshold -t "$((v-1)).5" -l 0 -h "$id" -m 0 "$atlas" "$tmp/a.mrc" >/dev/null
            clip threshold -t "$v.5" -l 0 -h "$id" -m 0 "$atlas" "$tmp/b.mrc" >/dev/null
            clip subtract "$tmp/a.mrc" "$tmp/b.mrc" "$tmp/c${id}_v$v.mrc" >/dev/null
            cparts+=("$tmp/c${id}_v$v.mrc")
            cvals+="${cvals:+, }$v"; clabs+="${clabs:+, }\"$nm\""
        done
        if [ ${#cparts[@]} -gt 1 ]; then
            clip add "${cparts[@]}" "$tmp/class$id.mrc" >/dev/null
        elif [ ${#cparts[@]} -eq 1 ]; then
            mv "${cparts[0]}" "$tmp/class$id.mrc"
        fi
        [ ${#cparts[@]} -gt 0 ] && parts+=("$tmp/class$id.mrc")
        vals[$id]="$cvals"; labs[$id]="$clabs"; nvals[$id]=${#cparts[@]}

        # csv points -> "object contour x y z radius" in pixels (IMOD -zcoord convention)
        npts=0
        if [ "${CLASS_RADIUS_A[$k]}" != 0 ]; then
            for nm in ${CLASS_ATLAS[$k]}; do
                [ -f "$run/zcoords_$nm.csv" ] || continue
                awk -F, -v o=$id -v p="$pix" -v r="${CLASS_RADIUS_A[$k]}" \
                    'NF>=3 {printf "%d 1 %.3f %.3f %.3f %.2f\n", o, $1/p, $2/p, $3/p, r/p}' \
                    "$run/zcoords_$nm.csv" >> "$pts"
                npts=$((npts + $(grep -c . "$run/zcoords_$nm.csv")))
            done
            [ $npts -gt 0 ] && maxobj=$id
        fi
        ncsv[$id]=$npts
    done

    # label volume: sum of the disjoint k*mask volumes (all zero if no class is present)
    if [ ${#parts[@]} -gt 1 ]; then
        clip add "${parts[@]}" "$out/labels.mrc" >/dev/null
    elif [ ${#parts[@]} -eq 1 ]; then
        cp "${parts[0]}" "$out/labels.mrc"
    else
        clip threshold -t 1e9 -l 0 -h 0 -m 0 "$atlas" "$out/labels.mrc" >/dev/null
    fi

    # voxel counts per class value
    local -A count=()
    while read -r value n; do count[$value]=$n; done < <(clip histogram "$out/labels.mrc" | \
        awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {print $1, $2}')

    if [ $masks -eq 1 ]; then
        for k in "${!CLASS_NAMES[@]}"; do
            local id=$((k+1))
            if [ "${nvals[$id]}" -gt 0 ]; then
                clip threshold -t 0.5 -l 0 -h 1 -m 0 "$tmp/class$id.mrc" "$out/mask_${CLASS_NAMES[$k]}.mrc" >/dev/null
            else
                clip threshold -t 1e9 -l 0 -h 0 -m 0 "$atlas" "$out/mask_${CLASS_NAMES[$k]}.mrc" >/dev/null
            fi
        done
    fi

    local modname="null"
    if [ $model -eq 1 ] && [ $maxobj -gt 0 ]; then
        local p2m=(point2model -scat -zcoord -sizes -sphere 1 -image "$ref")
        for k in "${!CLASS_NAMES[@]}"; do
            p2m+=(-name "${CLASS_NAMES[$k]}" -color "${CLASS_COLORS[$k]// /,}")
        done
        "${p2m[@]}" "$pts" "$out/particles.mod" >/dev/null
        modname='"particles.mod"'
    fi

    # labels.json
    json_classes="    {\"id\": 0, \"name\": \"background\", \"atlas_labels\": [], \"atlas_values\": [], \"present\": true, \"voxels\": ${count[0]:-0}, \"color\": [0, 0, 0], \"csv_points\": 0, \"mask_mrc\": null}"
    for k in "${!CLASS_NAMES[@]}"; do
        local id=$((k+1)) present=false mask=null
        [ "${nvals[$id]}" -gt 0 ] && present=true
        [ $masks -eq 1 ] && mask="\"mask_${CLASS_NAMES[$k]}.mrc\""
        json_classes+=$',\n'"    {\"id\": $id, \"name\": \"${CLASS_NAMES[$k]}\", \"atlas_labels\": [${labs[$id]}], \"atlas_values\": [${vals[$id]}], \"present\": $present, \"voxels\": ${count[$id]:-0}, \"color\": [${CLASS_COLORS[$k]// /, }], \"csv_points\": ${ncsv[$id]}, \"mask_mrc\": $mask}"
    done
    cat > "$out/labels.json" <<EOF
{
  "run": "$name",
  "atlas_mrc": "$(readlink -f "$atlas")",
  "atlas_txt": "$(readlink -f "$txt")",
  "reference_mrc": "$(readlink -f "$ref")",
  "pixel_size_A": $pix,
  "size_xyz": [$nx, $ny, $nz],
  "labels_mrc": "labels.mrc",
  "imod_model": $modname,
  "classes": [
$json_classes
  ]
}
EOF
    local missing=""
    for k in "${!CLASS_NAMES[@]}"; do [ "${nvals[$((k+1))]}" -gt 0 ] || missing+=" ${CLASS_NAMES[$k]}"; done
    echo "$name: pixel $pix A, ${nx}x${ny}x${nz}${missing:+, absent:$missing} -> $out"
}

for run in "${runs[@]}"; do
    convert_run "$run"
done
