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

# --- WATCHDOG RENDERER (PREVENTS CHROME FREEZES WITH RETRIES) ---
render_with_timeout() {
    local out_path="$1"
    local target_url="$2"
    local timeout=20
    local max_retries=5
    local attempt=1

    while (( attempt <= max_retries )); do
        "$CHROME_PATH" --headless=new --disable-gpu --disable-dev-shm-usage --no-sandbox --no-pdf-header-footer --print-to-pdf="$out_path" "$target_url" >/dev/null 2>&1 &
        local c_pid=$!
        
        # Spawn a background timer that will kill Chrome if it takes too long
        (
            sleep $timeout
            kill -9 $c_pid 2>/dev/null
        ) &
        local killer_pid=$!
        
        # Wait for Chrome to finish (or be killed)
        wait $c_pid 2>/dev/null
        
        # If Chrome finished naturally, kill the watchdog timer so it doesn't linger
        kill -9 $killer_pid 2>/dev/null

        # Check if the PDF was successfully generated and is not empty
        if [[ -s "$out_path" ]]; then
            break # Success! Break out of the retry loop.
        fi
        
        # If we reach here, the render failed or timed out.
        if (( attempt < max_retries )); then
            echo -e "         ${YELLOW}-> [RETRY $attempt/$max_retries] Timeout on: $target_url${RESET}"
        else
            echo -e "         ${DARK_RED}-> [FAILED] Given up after $max_retries retries: $target_url${RESET}"
        fi
        
        (( attempt++ ))
    done
}

# --- HEADER ASCII ART ---
print_header() {
    echo -e "${BLUE}${BOLD}"
    cat << 'EOF'
    ____    ___               ____                     _          ____  ____  ______
   /  _/___/ (_)________ _   / __ \____  __________   (_)___     / __ \/ __ \/ ____/
   / // __  / / ___/ __ `/  / / / / __ \/ ___/ ___/  / / __ \   / /_/ / / / / /_    
 _/ // /_/ / / /  / /_/ /  / /_/ / /_/ / /__(__  )  / / / / /  / ____/ /_/ / __/    
/___/\__,_/_/_/   \__,_/  /_____/\____/\___/____/  /_/_/ /_/  /_/   /_____/_/       
                                                                                    
EOF
    echo -e "${RESET}"
}

# --- HELP MENU ---
print_usage() {
    echo -e "${BOLD}Idira Docs Downloader CLI${RESET}\n"
    echo -e "${BOLD}Usage:${RESET} ./get_idira_docs.sh [OPTIONS]\n"
    echo -e "${BOLD}Modes (Choose one):${RESET}"
    echo -e "  ${CYAN}--list${RESET}         Fetch and list all available Idira document tiles and their ID numbers."
    echo -e "  ${CYAN}--all${RESET}          Download ALL available document tiles."
    echo -e "  ${CYAN}--tiles${RESET}        Comma-separated list or ranges of tile numbers to download (e.g., \"1, 3-5, 8\").\n"
    echo -e "${BOLD}Configuration Options:${RESET}"
    echo -e "  ${CYAN}--lang${RESET}         Languages to download (\"en\", \"ja\", or \"en,ja\"). Default: en,ja"
    echo -e "  ${CYAN}--depth${RESET}        Maximum nested link crawl depth. Default: 10"
    echo -e "  ${CYAN}--concurrency${RESET}  Number of concurrent parallel pages to download. Default: 10"
    echo -e "  ${CYAN}--engine${RESET}       Spider engine: 'chrome' (accurate, parses JS) or 'curl' (fast). Default: curl\n"
    echo -e "${BOLD}Examples:${RESET}"
    echo -e "  ./get_idira_docs.sh --list"
    echo -e "  ./get_idira_docs.sh --tiles \"1, 2-5\" --lang \"en\" --depth 3 --concurrency 10"
    echo -e "  ./get_idira_docs.sh --tiles \"38\" --engine chrome"
}

# ==========================================
# CONFIGURATION DEFAULTS
# ==========================================
ROOT_URL="https://docs.cyberark.com/portal/latest/en/docs.htm"
DEPTH_LIMIT=10 
CONCURRENCY=10 
ENGINE="curl" 
CHROME_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# ==========================================
# ARGUMENT PARSING
# ==========================================
MODE=""
TARGET_TILES=()
TARGET_LANGS=("en" "ja")
SHOW_USAGE_AFTER=false

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

if [[ "$MODE" != "list" ]] && [[ ! -f "$CHROME_PATH" ]]; then
    echo -e "${RED}[!] Google Chrome is required for rendering PDFs in Phase 2.${RESET}"
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

USER_AGENT='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36'
ROOT_HTML=$(curl -s -L -A "$USER_AGENT" "$ROOT_URL")

oldIFS=$IFS
IFS=$'\n'

TILE_DATA=()
while IFS= read -r line; do
    TILE_DATA+=("$line")
done < <(ROOT_HTML="$ROOT_HTML" python3 - <<'PY'
import os
import re
import html

html_text = os.environ["ROOT_HTML"]
html_text = re.sub(r'<!--.*?-->', '', html_text, flags=re.S)

current_category = ""
pattern = re.compile(
    r'<h2[^>]*class="[^"]*cat-title[^"]*"[^>]*>(?P<cat>.*?)</h2>|<div[^>]*class="[^"]*(?:portal-tile|space-tile)[^"]*"[^>]*>.*?<a[^>]*href=(?P<quote>["\'])(?P<url>.*?)(?P=quote)[^>]*>.*?<div[^>]*class="[^"]*(?:portal-tile-content|space-tile-content)[^"]*"[^>]*>(?P<content>.*?)</div>',
    flags=re.I | re.S,
)

for match in pattern.finditer(html_text):
    if match.group("cat") is not None:
        text = re.sub(r'<[^>]+>', '', html.unescape(match.group("cat")))
        current_category = re.sub(r'\s+', ' ', text).strip()
        continue

    url = match.group("url").strip()
    content = match.group("content")
    title_match = re.search(r'<p[^>]*>(.*?)</p>', content, flags=re.I | re.S)
    if not title_match:
        continue

    title = re.sub(r'<[^>]+>', '', html.unescape(title_match.group(1)))
    title = re.sub(r'\s+', ' ', title).strip()
    if not title:
        continue

    if current_category:
        title = f"{current_category} - {title}"

    title = re.sub(r'[^a-zA-Z0-9 \-&()]', '_', title)
    title = re.sub(r'\s+', ' ', title).strip()

    if url:
        url = re.sub(r'[#?].*$', '', url)
        print(f"{url}|{title}")
PY
)

IFS=$oldIFS
stop_spinner

# ==========================================
# LIST MODE: DISPLAY TILES AND EXIT
# ==========================================
if [[ "$MODE" == "list" ]]; then
    echo -e "\n${BLUE}${BOLD}=== AVAILABLE IDIRA TILES ===${RESET}"
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
        echo -e "  ${BOLD}./get_idira_docs.sh --tiles \"1, 3-5\" --lang \"en\"${RESET}"
    fi
    
    exit 0
fi

# ==========================================
# FILTER TILES BASED ON NUMERIC PARAMS & RANGES
# ==========================================
FILTERED_TILES=()
if [[ "$MODE" == "all" ]]; then
    FILTERED_TILES=("${TILE_DATA[@]}")
elif [[ "$MODE" == "tiles" ]]; then
    for t in "${TARGET_TILES[@]}"; do
        t_clean=$(echo "$t" | tr -d ' ')
        
        # Check if the input is a range (e.g., 2-5)
        if [[ "$t_clean" =~ ^[0-9]+-[0-9]+$ ]]; then
            start_val="${t_clean%%-*}"
            end_val="${t_clean##*-}"
            
            if (( start_val <= end_val )); then
                for (( i=start_val; i<=end_val; i++ )); do
                    if (( i > 0 )) && (( i <= ${#TILE_DATA[@]} )); then
                        FILTERED_TILES+=("${TILE_DATA[$i]}")
                    else
                        echo -e "${RED}[-] Invalid tile number in range: '$i'. Skipping.${RESET}"
                    fi
                done
            else
                echo -e "${RED}[-] Invalid range: '$t_clean'. Start must be less than or equal to End. Skipping.${RESET}"
            fi
            
        # Check if the input is a single number
        elif [[ "$t_clean" =~ ^[0-9]+$ ]]; then
            if (( t_clean > 0 )) && (( t_clean <= ${#TILE_DATA[@]} )); then
                FILTERED_TILES+=("${TILE_DATA[$t_clean]}")
            else
                echo -e "${RED}[-] Invalid tile number: '$t_clean'. Skipping.${RESET}"
            fi
        else
            echo -e "${RED}[-] Invalid tile format: '$t_clean'. Use single numbers or ranges (e.g., '1', '2-5'). Skipping.${RESET}"
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
                            http_code=$(curl -s -L -A "$USER_AGENT" -w "%{http_code}" -o "$html_path" "$current_url")
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
                            "$CHROME_PATH" --headless=new --disable-gpu --disable-dev-shm-usage --no-sandbox --dump-dom --virtual-time-budget=5000 "$current_url" > "$html_path" 2>/dev/null
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
                
                # Hand over rendering to the Watchdog function with built-in retries
                render_with_timeout "$pdf_path" "$current_url" &
                
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