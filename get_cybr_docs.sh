#!/bin/zsh

# ==========================================
# UI & COLOR CONFIGURATION
# ==========================================
RESET='\033[0m'
BOLD='\033[1m'
RED='\033[1;31m'
DARK_RED='\033[0;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
GRAY='\033[0;90m'

# --- SAFETY TRAP FOR CTRL-C ---
trap 'tput cnorm; echo -e "\n\n${RED}[!] Ctrl-C detected! Terminating background jobs...${RESET}"; kill $(jobs -p) 2>/dev/null; kill $SPIN_PID 2>/dev/null; pkill -P $$ 2>/dev/null; exit 1' INT TERM

# --- SPINNER FUNCTION ---
start_spinner() {
    local msg="$1"
    echo -n -e "${CYAN}${msg}${RESET} "
    tput civis 
    (
        local spinstr='-\|/'
        while true; do
            local temp=${spinstr#?}
            printf "${CYAN}%c${RESET}" "$spinstr"
            local spinstr=$temp${spinstr%"$temp"}
            sleep 0.1
            printf "\b"
        done
    ) &
    SPIN_PID=$!
}

stop_spinner() {
    kill $SPIN_PID 2>/dev/null
    wait $SPIN_PID 2>/dev/null
    tput cnorm 
    echo -e "${GREEN}[Done]${RESET}"
}

# --- HEADER ASCII ART ---
print_header() {
    echo -e "${BLUE}${BOLD}"
    cat << 'EOF'
   _____   _____ ___   ___               _        ___ ___  ___ 
  / __\ \ / / _ ) _ \ |   \ ___  __ ___ (_)_ _   | _ \   \| __|
 | (__ \ V /| _ \   / | |) / _ \/ _(_-< | | ' \  |  _/ |) | _| 
  \___| |_| |___/_|_\ |___/\___/\__/__/ |_|_||_| |_| |___/|_|  
EOF
    echo -e "${RESET}"
}

# --- HELP MENU ---
print_usage() {
    echo -e "${BOLD}CyberArk Docs Downloader CLI${RESET}\n"
    echo -e "${BOLD}Usage:${RESET} zsh $0 [OPTIONS]\n"
    echo -e "${BOLD}Modes (Choose one):${RESET}"
    echo -e "  ${CYAN}--list${RESET}         Fetch and list all available CyberArk document tiles and their ID numbers."
    echo -e "  ${CYAN}--all${RESET}          Download ALL available document tiles."
    echo -e "  ${CYAN}--tiles${RESET}        Comma-separated list of tile numbers to download (e.g., \"1, 2, 5\").\n"
    echo -e "${BOLD}Configuration Options:${RESET}"
    echo -e "  ${CYAN}--lang${RESET}         Languages to download (\"en\", \"ja\", or \"en,ja\"). Default: en,ja"
    echo -e "  ${CYAN}--depth${RESET}        Maximum nested link crawl depth. Default: 10"
    echo -e "  ${CYAN}--concurrency${RESET}  Number of concurrent parallel pages to download. Default: 10"
    echo -e "  ${CYAN}--engine${RESET}       Spider engine: 'chrome' (accurate, parses JS) or 'curl' (fast). Default: curl\n"
    echo -e "${BOLD}Examples:${RESET}"
    echo -e "  zsh $0 --list"
    echo -e "  zsh $0 --tiles \"1, 2\" --lang \"en\" --depth 3 --concurrency 10"
    echo -e "  zsh $0 --tiles \"38\" --engine chrome"
}

# ==========================================
# CONFIGURATION DEFAULTS
# ==========================================
ROOT_URL="https://docs.cyberark.com/portal/latest/en/docs.htm"
DEPTH_LIMIT=10 
CONCURRENCY=10 
ENGINE="curl" 
CHROME_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

if [[ ! -f "$CHROME_PATH" ]]; then
    echo -e "${RED}[!] Google Chrome is required for rendering PDFs in Phase 2.${RESET}"
    exit 1
fi

# ==========================================
# ARGUMENT PARSING
# ==========================================
MODE=""
TARGET_TILES=()
TARGET_LANGS=("en" "ja")
SHOW_USAGE_AFTER=false

# Always show the header as soon as the script starts
print_header

if [[ "$#" -eq 0 ]]; then
    MODE="list"
    SHOW_USAGE_AFTER=true
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --list) MODE="list"; shift ;;
        --all) MODE="all"; shift ;;
        --tiles) MODE="tiles"; TARGET_TILES=("${(@s/,/)2}"); shift 2 ;;
        --lang) TARGET_LANGS=("${(@s/,/)2}"); shift 2 ;;
        --depth) DEPTH_LIMIT="$2"; shift 2 ;;
        --concurrency) CONCURRENCY="$2"; shift 2 ;;
        --engine) ENGINE="$2"; shift 2 ;;
        *)
            echo -e "${RED}[!] Unknown parameter: $1${RESET}\n"
            print_usage
            exit 1
            ;;
    esac
done

if [[ -z "$MODE" ]]; then
    echo -e "${RED}[!] You must specify a primary mode: --list, --all, or --tiles.${RESET}"
    exit 1
fi

# ==========================================
# URL RESOLVER (WITH NORMALIZATION)
# ==========================================
resolve_url() {
    local base="$1"
    local link="$2"
    local full_url=""
    
    link="${link%%#*}"
    link="${link%%\?*}"
    
    if [[ "$link" == http* ]]; then
        full_url="$link"
    elif [[ "$link" == /* ]]; then
        full_url="https://docs.cyberark.com$link"
    else
        full_url="${base%/*}/$link"
    fi
    
    echo "$full_url" | perl -pe '1 while s#(?<!:)/[^/]+/\.\.(/|$)#/#;'
}

# ==========================================
# EXTRACT TILES WITH CATEGORY CONTEXT
# ==========================================
if [[ "$MODE" == "list" ]]; then
    start_spinner "[*] Fetching available document tiles from $ROOT_URL..."
else
    start_spinner "[*] Loading Portal Root: $ROOT_URL..."
fi

ROOT_HTML=$(curl -s -L "$ROOT_URL")

oldIFS=$IFS
IFS=$'\n'

# Using hex escapes (\x3C and \x3E) to strip HTML comments without breaking chat UI rendering
TILE_DATA=($(echo "$ROOT_HTML" | perl -0777 -ne '
    s/\x3C!--.*?--!?\x3E//gs; 
    my $cat = "";
    while (m{<h2[^>]*class="cat-title"[^>]*>(.*?)</h2>|<div[^>]*class="[^"]*(?:portal-tile|space-tile)[^"]*"[^>]*>.*?href=(["\x27])([^"\x27]+)\2.*?(?:<p[^>]*>)(.*?)</p>}gis) {
        if ($1) {
            $cat = $1;
            $cat =~ s/<[^>]+>//g;
            $cat =~ s/^\s+|\s+$//g;
        } elsif ($3 && $4) {
            my $url = $3;
            my $title = $4;
            
            $url =~ s/[#?].*//;
            $title =~ s/<[^>]+>//g;
            $title =~ s/&amp;/&/ig;
            $title =~ s/&#160;/ /ig;
            $title =~ s/&nbsp;/ /ig;
            $title =~ s/&#39;/\x27/ig;
            $title =~ s/^\s+|\s+$//g;
            
            my $full_name = $title;
            if ($cat ne "" && $cat !~ /Spaces/i) {
                $full_name = "$cat - $title";
            }
            
            $full_name =~ s/[^a-zA-Z0-9 \-&()]/_/g;
            $full_name =~ s/\s+/ /g;
            $full_name =~ s/^\s+|\s+$//g;
            
            print "$url|$full_name\n" if $url ne "";
        }
    }
'))

IFS=$oldIFS
stop_spinner

# ==========================================
# LIST MODE: DISPLAY TILES AND EXIT
# ==========================================
if [[ "$MODE" == "list" ]]; then
    echo -e "\n${BLUE}${BOLD}=== AVAILABLE CYBERARK TILES ===${RESET}"
    count=1
    for item in "${TILE_DATA[@]}"; do
        title=$(echo "$item" | cut -d'|' -f2)
        printf " ${CYAN}[%2d]${RESET} %s\n" "$count" "$title"
        ((count++))
    done
    echo -e "${BLUE}${BOLD}================================${RESET}"
    
    if [[ "$SHOW_USAGE_AFTER" == true ]]; then
        echo ""
        print_usage
    else
        echo -e "\nTo download, run the script with parameters using the numbers above:"
        echo -e "  ${BOLD}zsh $0 --tiles \"1, 2\" --lang \"en\"${RESET}"
    fi
    
    exit 0
fi

# ==========================================
# FILTER TILES BASED ON NUMERIC PARAMS
# ==========================================
FILTERED_TILES=()
if [[ "$MODE" == "all" ]]; then
    FILTERED_TILES=("${TILE_DATA[@]}")
elif [[ "$MODE" == "tiles" ]]; then
    for t in "${TARGET_TILES[@]}"; do
        t_clean=$(echo "$t" | tr -d ' ')
        if [[ "$t_clean" =~ ^[0-9]+$ ]] && (( t_clean > 0 )) && (( t_clean <= ${#TILE_DATA[@]} )); then
            FILTERED_TILES+=("${TILE_DATA[$t_clean]}")
        else
            echo -e "${RED}[-] Invalid tile number: '$t'. Skipping.${RESET}"
        fi
    done
fi

if (( ${#FILTERED_TILES[@]} == 0 )); then
    echo -e "${RED}[-] No valid matching tiles found. Exiting.${RESET}"
    exit 1
fi

echo -e "\n${BOLD}[*] Configuration -> Depth Limit: ${CYAN}$DEPTH_LIMIT${RESET}${BOLD} | Concurrency: ${CYAN}$CONCURRENCY${RESET}${BOLD} | Spider Engine: ${CYAN}${(U)ENGINE}${RESET}"
echo -e "${BOLD}[*] Proceeding with ${CYAN}${#FILTERED_TILES[@]}${RESET}${BOLD} selected tiles for languages: ${CYAN}${(j:, :)TARGET_LANGS}${RESET}${BOLD}...${RESET}"

# ==========================================
# PROCESS SELECTED TILES
# ==========================================
for item in "${FILTERED_TILES[@]}"; do
    raw_url=$(echo "$item" | cut -d'|' -f1)
    title=$(echo "$item" | cut -d'|' -f2)
    
    tile_url=$(resolve_url "$ROOT_URL" "$raw_url")
    product_base="${tile_url%%/latest/*}"
    
    for lang in "${TARGET_LANGS[@]}"; do
        lang=$(echo "$lang" | tr -d ' ')
        lang_url=$(echo "$tile_url" | sed -e "s|/latest/[a-z]*/|/latest/${lang}/|")
        pdf_name="${title}_${lang}.pdf"
        temp_dir="temp_${title// /_}_${lang}"
        
        echo -e "\n${BLUE}========================================================================${RESET}"
        echo -e "${BOLD}${GREEN}[+] Processing Document:${RESET} ${BOLD}$pdf_name${RESET}"
        echo -e "${BLUE}========================================================================${RESET}"
        mkdir -p "$temp_dir"
        
        typeset -A VISITED
        typeset -A FAILED_URLS
        QUEUE=("$lang_url")
        VISITED[$lang_url]=1
        MASTER_URL_LIST=("$lang_url")
        
        # ------------------------------------------
        # PHASE 1: CRAWLING (DUAL ENGINE)
        # ------------------------------------------
        echo -e "${MAGENTA}${BOLD}    -> PHASE 1: Crawling URLs via ${(U)ENGINE} (Depth Limit: $DEPTH_LIMIT)${RESET}"
        for (( depth=0; depth<=DEPTH_LIMIT; depth++ )); do
            if (( ${#QUEUE[@]} == 0 )); then break; fi
            echo -e "       ${CYAN}[Depth $depth]${RESET} Mapping ${#QUEUE[@]} pages..."
            
            NEXT_QUEUE=()
            
            for (( i=1; i<=${#QUEUE[@]}; i+=CONCURRENCY )); do
                for (( j=0; j<CONCURRENCY; j++ )); do
                    idx=$((i + j))
                    if (( idx > ${#QUEUE[@]} )); then break; fi
                    
                    current_url="${QUEUE[$idx]}"
                    html_path="${temp_dir}/dom_d${depth}_${idx}.html"
                    
                    if [[ "$ENGINE" == "curl" ]]; then
                        echo -e "         ${GRAY}-> [cURL] Fetching: $current_url${RESET}"
                        (
                            http_code=$(curl -s -L -w "%{http_code}" -o "$html_path" "$current_url")
                            if [[ "$http_code" -ge 400 ]] || [[ "$http_code" == "000" ]]; then
                                echo -e "         ${DARK_RED}-> [SKIP] HTTP $http_code (Dead Link): $current_url${RESET}"
                                rm -f "$html_path"
                            else
                                echo -e "         ${YELLOW}-> [cURL] Success: $current_url${RESET}"
                            fi
                        ) &
                    else
                        echo -e "         ${GRAY}-> [CHROME] Rendering DOM: $current_url${RESET}"
                        (
                            "$CHROME_PATH" --headless=new --dump-dom --virtual-time-budget=3000 "$current_url" > "$html_path" 2>/dev/null
                            if [[ ! -s "$html_path" ]]; then
                                rm -f "$html_path"
                            else
                                echo -e "         ${YELLOW}-> [CHROME] Success: $current_url${RESET}"
                            fi
                        ) &
                    fi
                done
                wait 
            done
            
            for (( i=1; i<=${#QUEUE[@]}; i++ )); do
                current_url="${QUEUE[$i]}"
                html_path="${temp_dir}/dom_d${depth}_${i}.html"
                
                if [[ ! -f "$html_path" ]]; then
                    FAILED_URLS[$current_url]=1
                    continue
                fi
                
                if (( depth < DEPTH_LIMIT )); then
                    # Using hex escapes (\x3C and \x3E) here as well to strip comments
                    sub_links=($(cat "$html_path" | perl -0777 -ne 's/\x3C!--.*?--!?\x3E//gs; while (/href=(["\x27])([^"\x27]+)\1/g) { my $l=$2; next if $l=~/\[%/; $l=~s/[#?].*//; print "$l\n" if $l; }' | sort -u))
                    
                    for sub in "${sub_links[@]}"; do
                        case "$sub" in
                            *.css|*.js|*.png|*.jpg|*.jpeg|*.gif|*.svg|*.ico|*.woff|*.woff2|*.ttf|*\[%*) continue ;;
                        esac
                        
                        full_sub=$(resolve_url "$current_url" "$sub")
                        
                        setopt nocasematch
                        if [[ "$full_sub" == "${product_base}"*"/latest/${lang}/"* ]]; then
                            if [[ -z "${VISITED[$full_sub]}" ]]; then
                                NEXT_QUEUE+=("$full_sub")
                                MASTER_URL_LIST+=("$full_sub")
                                VISITED[$full_sub]=1
                            fi
                        fi
                        unsetopt nocasematch
                    done
                fi
            done
            QUEUE=("${NEXT_QUEUE[@]}")
        done
        
        # ------------------------------------------
        # PHASE 2: BATCH PDF GENERATION (CHROME)
        # ------------------------------------------
        VALID_MASTER_URL_LIST=()
        for url in "${MASTER_URL_LIST[@]}"; do
            if [[ -z "${FAILED_URLS[$url]}" ]]; then
                VALID_MASTER_URL_LIST+=("$url")
            fi
        done
        
        TOTAL_PAGES=${#VALID_MASTER_URL_LIST[@]}
        echo -e "\n${MAGENTA}${BOLD}    -> PHASE 2: Generating PDFs for $TOTAL_PAGES validated pages...${RESET}"
        
        PDF_FILES=()
        for (( i=1; i<=TOTAL_PAGES; i+=CONCURRENCY )); do
            batch_end=$(( i+CONCURRENCY-1 > TOTAL_PAGES ? TOTAL_PAGES : i+CONCURRENCY-1 ))
            printf "       ${CYAN}[CHROME]${RESET} Rendering batch %d to %d (out of %d)...\n" $i $batch_end $TOTAL_PAGES
            
            for (( j=0; j<CONCURRENCY; j++ )); do
                idx=$((i + j))
                if (( idx > TOTAL_PAGES )); then break; fi
                
                current_url="${VALID_MASTER_URL_LIST[$idx]}"
                printf_idx=$(printf "%04d" $idx)
                pdf_path="${temp_dir}/page_${printf_idx}.pdf"
                
                "$CHROME_PATH" --headless=new --no-pdf-header-footer --print-to-pdf="$pdf_path" "$current_url" 2>/dev/null &
            done
            wait 
        done
        
        for (( i=1; i<=TOTAL_PAGES; i++ )); do
            printf_idx=$(printf "%04d" $i)
            pdf_path="${temp_dir}/page_${printf_idx}.pdf"
            if [[ -f "$pdf_path" ]]; then
                PDF_FILES+=("$(PWD)/$pdf_path")
            fi
        done
        
        # ------------------------------------------
        # PHASE 3: IN-MEMORY NATIVE MERGING
        # ------------------------------------------
        echo ""
        if (( ${#PDF_FILES[@]} > 0 )); then
            out_file="$(PWD)/${pdf_name}"
            
            start_spinner "    ${MAGENTA}${BOLD}-> PHASE 3:${RESET} Binding ${CYAN}${#PDF_FILES[@]}${RESET} pages natively in memory..."
            
            osascript -l JavaScript - "$out_file" "${PDF_FILES[@]}" << 'EOF'
ObjC.import('Quartz');
function run(argv) {
    if (argv.length < 2) return;
    var outFile = argv.shift();
    var outDoc = $.PDFDocument.alloc.init;
    var pageIndex = 0;
    
    argv.forEach(file => {
        var doc = $.PDFDocument.alloc.initWithURL($.NSURL.fileURLWithPath(file));
        if (doc != undefined) {
            for (var j = 0; j < doc.pageCount; j++) {
                outDoc.insertPageAtIndex(doc.pageAtIndex(j), pageIndex++);
            }
        }
    });
    outDoc.writeToFile(outFile);
}
EOF
            stop_spinner
            echo -e "       ${GREEN}${BOLD}[SUCCESS] Final Document Saved:${RESET} $out_file"
        else
            echo -e "       ${RED}[-] No valid pages found or rendered for ${lang_url}.${RESET}"
        fi
        
        rm -rf "$temp_dir"
    done
done

echo -e "\n${GREEN}${BOLD}[*] All tasks complete.${RESET}"
