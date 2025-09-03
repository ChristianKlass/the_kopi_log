#!/bin/bash

API_KEY="${GOOGLE_API_KEY}"

# The number of top-ranked articles to generate per run.
ARTICLES_TO_GENERATE=1

RSS_FEEDS=(
    "https://www.theverge.com/rss/index.xml"
    "https://www.engadget.com/rss/xml"
    "https://www.rockpapershotgun.com/feed"
    "https://kotaku.com/rss"
    "https://hackaday.com/feed/"
    "https://www.eurogamer.net/feed"
    "https://www.hardwarezone.com.sg/rss"
    "https://www.reddit.com/r/Games/.rss"
    "https://www.reddit.com/r/pcgaming/.rss"
    "https://www.reddit.com/r/3Dprinting/.rss"
)

HIGH_VALUE_KEYWORDS=(
    "GTA" "Grand Theft Auto" "Rockstar Games"
    "Nvidia" "AMD" "PlayStation"
    "Prusaslicer" "Bambu Studio"
    "Xbox" "Nintendo" "Linux" "Asus" "ROG"
)
LOW_VALUE_KEYWORDS=(
    "review" "gaming" "launches" "announced" "released"
    "laptop" "iPhone" "Android" "Pixel" "Intel"
    "Bambu Lab" "Prusa" "Creality" "Ultimaker" "MakerBot" "3D Print"
)
EVENT_KEYWORDS=(
    "Comic Con" "IT Show" "Gamescom Asia" "AFA" "Anime Festival Asia"
    "COMEX" "SITEX" "Singapore Fintech Festival" "Apple Event" "WWDC"
    "Google I/O" "CES" "Computex" "Microsoft Build" "The Game Awards"
    "Summer Game Fest" "BlizzCon" "PAX" "EGX" "LTX" "TwitchCon"
)

OUTPUT_DIR="./blog/content/posts"
IMAGE_DIR="./blog/static/images"
STATE_FILE="./.hobby_news_tracker.log"
EVENT_TRACKER_FILE="./.event_tracker.log"
mkdir -p "$OUTPUT_DIR"
mkdir -p "$IMAGE_DIR"
touch "$STATE_FILE"
touch "$EVENT_TRACKER_FILE"

check_dependencies() {
    for cmd in curl xmlstarlet jq perl date base64; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Error: Required command '$cmd' is not installed." >&2; exit 1
        fi
    done
    if [ -z "$API_KEY" ]; then
        echo "Error: GOOGLE_API_KEY environment variable is not set." >&2; exit 1
    fi
}

generate_and_save_image() {
    local image_prompt="$1"
    local output_path="$2"
    echo "  -> Generating image with prompt: \"$image_prompt\""
    local json_payload
    json_payload=$(jq -n --arg prompt "$image_prompt" \
      '{ "instances": [{ "prompt": $prompt }], "parameters": { "sampleCount": 1 } }')
    local api_response
    api_response=$(curl -s -X POST -H "Content-Type: application/json" -d "$json_payload" \
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:predict?key=${API_KEY}")
    echo "  -> Image API Response: $api_response"
    local base64_data
    base64_data=$(echo "$api_response" | jq -r '.predictions[0].bytesBase64Encoded')
    if [ -z "$base64_data" ] || [ "$base64_data" == "null" ]; then
        echo "  -> Error: Image generation failed or returned no data." >&2
        return 1
    fi
    echo "$base64_data" | base64 --decode > "$output_path"
    echo "  -> Image saved to: $output_path"
    return 0
}

generate_event_article() {
    local title="$1"
    local link="$2"
    local description="$3"
    local event_name="$4"

    local sanitized_title=$(echo "$title" | tr -cd '[:alnum:] ' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    local filename_base="$(date +%Y-%m-%d)-${sanitized_title}"
    local output_file="${OUTPUT_DIR}/${filename_base}.md"
    local image_output_path="${IMAGE_DIR}/${filename_base}.png"
    local image_path_relative="/images/${filename_base}.png"

    echo "  -> Generating special event article for: \"$title\""

    local prompt_template="You are a local tech and culture guide in Singapore. Your task is to write a short, informative announcement about an upcoming event.
        Your primary goal is to find and include practical details like the official website, dates, and location. 
        Use your search tool to find this information if it is not in the provided source text.
        - **Headline:** Create a catchy headline that clearly states the event (8-10 words max).
        - **Body:** Explain what the event is, what attendees can expect, and why it's worth checking out. Weave in the practical details (dates, location, website) you found.
        **IMPORTANT:**
        - If you cannot find a specific detail (like the official website) after searching, simply omit it.
        - **Do not use placeholders like '[Insert Date Here]' under any circumstances.**
        - The final output should be a cohesive article. Do not use numbered lists or explicit section headers."

    local json_payload
    json_payload=$(jq -n \
      --arg prompt "$prompt_template" \
      --arg title "$title" \
      --arg link "$link" \
      --arg summary "$description" \
      '{
        "contents": [{
          "parts": [{
            "text": ($prompt + "\n\nWrite the announcement based on this source article:\n- Title: \"" + $title + "\"\n- Link: " + $link + "\n- Summary: \"" + $summary + "\"")
          }]
        }],
        "tools": [{"google_search": {}}]
      }')

    local api_response
    api_response=$(curl -s -H "Content-Type: application/json" -d "$json_payload" "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=${API_KEY}")

    if ! jq -e '.candidates[0].content.parts[0].text' > /dev/null <<< "$api_response"; then
        echo "  -> Error: API call failed." >&2
        echo "  -> API Response: $api_response" >&2
        return 1
    fi

    local generated_text=$(echo "$api_response" | jq -r '.candidates[0].content.parts[0].text')
    local image_prompt="A vibrant, exciting promotional graphic for the event: ${event_name} in Singapore"
    if ! generate_and_save_image "$image_prompt" "$image_output_path"; then
        image_path_relative=""
    fi

    local source_line=$(printf '\n\n*Based on information from [%s](%s).*' "$title" "$link")
    local final_content=$(printf "%b" "${generated_text}${source_line}")

    cat > "$output_file" <<-EOF
---
title: "$(echo "$title" | sed 's/"/\\"/g')"
date: $(date --iso-8601=seconds)
draft: false
tags: ["Event", "Singapore"]
images: ["$image_path_relative"]
---
$final_content
EOF

    echo "  -> Successfully saved event article to: ${output_file}"
    echo "$(date +%Y-%m-%d):$event_name" >> "$EVENT_TRACKER_FILE"
}

check_for_local_events() {
    echo "EVENT WATCHER: Checking for major upcoming local events..."
    local today_epoch=$(date +%s)
    local seven_days_ago_epoch=$((today_epoch - 604800))

    for event in "${EVENT_KEYWORDS[@]}"; do
        local last_covered_date=$(grep ":$event" "$EVENT_TRACKER_FILE" | tail -n 1 | cut -d':' -f1)
        if [ -n "$last_covered_date" ]; then
            local last_covered_epoch=$(date -d "$last_covered_date" +%s)
            if [ "$last_covered_epoch" -gt "$seven_days_ago_epoch" ]; then
                echo "  - Already covered '$event' recently. Skipping."
                continue
            fi
        fi

        for feed_url in "${RSS_FEEDS[@]}"; do
            local articles=$(curl -sL --compressed -A "Mozilla/5.0" "$feed_url" | \
                xmlstarlet sel -t -m "//*[local-name()='item' or local-name()='entry'][contains(translate(./*[local-name()='title'], 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), '$(echo "$event" | tr '[:upper:]' '[:lower:]')')]" \
                -v "concat(normalize-space(*[local-name()='link' and not(@href)]|*[local-name()='link']/@href), '^', normalize-space(*[local-name()='title']), '^', normalize-space(*[local-name()='description' or local-name()='summary' or local-name()='content']))" -n 2>/dev/null)
            
            if [ -n "$articles" ]; then
                local article_data=$(echo "$articles" | head -n 1)
                IFS='^' read -r link title description <<< "$article_data"
                if [ -z "$title" ]; then continue; fi
                echo "  - Found upcoming event article: '$title'"
                # --- FIX: Check if generation succeeds before returning ---
                if generate_event_article "$title" "$link" "$description" "$event"; then
                    return 0 # Generation was successful, so we can exit the function.
                else
                    echo "EVENT WATCHER: Generation for '$title' failed. Continuing search..."
                    # Continue the loops to check other feeds/events
                fi
            fi
        done
    done
    echo "EVENT WATCHER: No new major events found or all attempts failed."
    return 1 # Return failure if no article was successfully generated
}

generate_article_from_cluster() {
    local articles_array=("$@")
    IFS='^' read -r p_score p_guid p_link p_title p_description <<< "${articles_array[0]}"
    if [ -z "$p_title" ]; then echo "  -> Error: Primary article has no title." >&2; return 1; fi

    local sanitized_title=$(echo "$p_title" | tr -cd '[:alnum:] ' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    local filename_base="$(date +%Y-%m-%d)-${sanitized_title}"
    local output_file="${OUTPUT_DIR}/${filename_base}.md"
    
    echo "  -> Generating synthesized blog post for topic: \"$p_title\""
    echo "  -> Using ${#articles_array[@]} sources."
    echo "  -> Saving to Hugo path: ${output_file}"

    local prompt_template="You are a tech journalist based in Singapore, writing for a local audience. Your tone is conversational, informed, and practical. Maintain a direct, no-nonsense style that a local reader would find helpful and authentic. Avoid overt slang. Do not hide the fact that you're an AI.

Your task is to synthesize the news from the provided sources and offer a clear, opinionated analysis.

Your article should be a cohesive piece that flows naturally. Start with a catchy, informal headline (8-10 words max). Then, weave together a summary of the news with your own analysis. As you analyze, naturally incorporate a local perspective. For example, consider local pricing, availability, and whether it's a good fit for the market here. Conclude with a clear recommendation or a final thought.

**IMPORTANT:**
- Your analysis must be grounded strictly in the provided sources. 
    If a crucial detail is missing, use your search tool to find context, but do not state information that cannot be verified.
- **Do not use placeholders like '[Insert Name Here]' under any circumstances. If a detail is unknown, omit it.**
- The final output should be a single, cohesive article. Do not use numbered lists or explicit section headers like 'Analysis' or 'Conclusion'.
- The headline should be catchy and informal, but do not label it as 'Headline' in the output. It should be 8-10 words max.
- **Get straight to the point. Do not use conversational greetings like 'Hey everyone'.**
- Do not invent personal experiences."

    local sources_for_prompt=""
    local source_counter=1
    for article_data in "${articles_array[@]}"; do
        IFS='^' read -r score guid link title description <<< "$article_data"
        local clean_desc=$(echo "$description" | sed -e 's/<[^>]*>//g')
        sources_for_prompt+=$(printf "\n--- Source %d ---\nTitle: %s\nLink: %s\nSummary: %s\n" "$source_counter" "$title" "$link" "$clean_desc")
        ((source_counter++))
    done

    local json_payload
    json_payload=$(jq -n \
      --arg prompt "$prompt_template" \
      --arg sources "$sources_for_prompt" \
      '{
        "contents": [{
          "parts": [{
            "text": ($prompt + "\n\nSynthesize the following sources:\n" + $sources)
          }]
        }],
        "tools": [{"google_search": {}}]
      }')

    local api_response
    api_response=$(curl -s -H "Content-Type: application/json" -d "$json_payload" \
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=${API_KEY}")

    if ! jq -e '.candidates[0].content.parts[0].text' > /dev/null <<< "$api_response"; then
        echo "  -> Error: API call failed or response format was unexpected." >&2
        echo "  -> API Response: $api_response" >&2
        return 1
    fi

    local generated_text=$(echo "$api_response" | jq -r '.candidates[0].content.parts[0].text')
    
    local image_path_relative=""
    local image_prompt="A minimalist, abstract digital art representing the concept of '${p_title}'"
    local image_output_path="${IMAGE_DIR}/${filename_base}.png"
    
    if generate_and_save_image "$image_prompt" "$image_output_path"; then
        image_path_relative="/images/${filename_base}.png"
    fi

    local source_line="\n\n*This analysis is based on reporting from the following sources:*"
    for article_data in "${articles_array[@]}"; do
        IFS='^' read -r score guid link title description <<< "$article_data"
        source_line+=$(printf '\n- [%s](%s)' "$title" "$link")
    done
    
    local final_content
    final_content=$(printf "%b" "${generated_text}${source_line}")

    cat > "$output_file" <<-EOF
---
title: "$(echo "$p_title" | sed 's/"/\\"/g')"
date: $(date --iso-8601=seconds)
draft: false
images: ["$image_path_relative"]
---
$final_content
EOF

    echo "  -> Successfully saved article to: ${output_file}"
}

main() {
    local debug_mode=false
    if [[ "$1" == "--debug" ]]; then debug_mode=true; echo "--- RUNNING IN DEBUG MODE ---"; fi

    check_dependencies

    if [ "$debug_mode" = false ]; then
        if check_for_local_events; then
            echo "Event article generated. Exiting regular news cycle for this run."
            exit 0
        fi
    fi
    
    echo "STAGE 1: Scanning all feeds for candidate articles..."
    
    local all_keywords=("${HIGH_VALUE_KEYWORDS[@]}" "${LOW_VALUE_KEYWORDS[@]}")
    local keyword_pattern=$(IFS='|'; echo "${all_keywords[*]}")
    declare -a candidate_articles

    for feed_url in "${RSS_FEEDS[@]}"; do
        echo "  - Fetching feed: $feed_url"
        local articles
        articles=$(curl -sL --compressed -A "Mozilla/5.0" "$feed_url" | \
            xmlstarlet sel -t -m "//*[local-name()='item' or local-name()='entry']" \
            -v "concat(normalize-space(*[local-name()='guid' or local-name()='id']), '^', 
                normalize-space(*[local-name()='link' and not(@href)]|*[local-name()='link']/@href), '^', 
                normalize-space(*[local-name()='title']), '^', normalize-space(*[local-name()='description' or local-name()='summary' or local-name()='content']))" -n 2>/dev/null)
        
        if [ -z "$articles" ]; then continue; fi

        while IFS='^' read -r guid link title description; do
            [ -z "$guid" ] && guid="$link"
            if grep -qF "$guid" "$STATE_FILE"; then continue; fi
            if [ -z "$title" ] || [ -z "$link" ]; then continue; fi

            local clean_text=$(echo "$title $description" | perl -MHTML::Entities -pe 'decode_entities($_)')
            if echo "$clean_text" | grep -iqE "$keyword_pattern"; then
                candidate_articles+=("$(printf "%s^%s^%s^%s" "$guid" "$link" "$title" "$description")")
            fi
        done <<< "$articles"
    done
    echo "Found ${#candidate_articles[@]} potential new articles."

    echo -e "\nSTAGE 2: Ranking candidates..."
    
    declare -a scored_articles
    for article_data in "${candidate_articles[@]}"; do
        IFS='^' read -r guid link title description <<< "$article_data"
        local content="$title $description"
        local score=0
        local high_value_pattern=$(IFS='|'; echo "${HIGH_VALUE_KEYWORDS[*]}")
        local high_matches=$(echo "$content" | grep -ioE "$high_value_pattern" | wc -l)
        score=$((score + high_matches * 5))
        local low_value_pattern=$(IFS='|'; echo "${LOW_VALUE_KEYWORDS[@]}")
        local low_matches=$(echo "$content" | grep -ioE "$low_value_pattern" | wc -l)
        score=$((score + low_matches * 2))
        if [ "$score" -gt 0 ]; then scored_articles+=("$(printf "%d^%s^%s^%s^%s" "$score" "$guid" "$link" "$title" "$description")"); fi
    done

    mapfile -t sorted_articles < <(printf "%s\n" "${scored_articles[@]}" | sort -t'^' -rnk1)
    
    if [ ${#sorted_articles[@]} -eq 0 ]; then echo "No articles met the criteria to be ranked. Exiting."; exit 0; fi
    
    echo -e "\nSTAGE 3: Finding related articles for synthesis..."
    
    local primary_article="${sorted_articles[0]}"
    IFS='^' read -r p_score p_guid p_link p_title p_description <<< "$primary_article"
    declare -a article_cluster=("$primary_article")
    
    local stop_words="a|an|and|are|as|at|be|by|for|from|how|in|is|it|of|on|or|that|the|this|to|was|what|when|where|who|will|with|the|we|played|i|my|me|is|not|just"
    local primary_keywords=($(echo "$p_title" | tr '[:upper:]' '[:lower:]' | tr -sc 'a-zA-Z0.9' '\n' | grep '...' | grep -viE "^($stop_words)$"))
    local max_sources=3
    local sources_found=1

    for (( i=1; i<${#sorted_articles[@]}; i++ )); do
        if [ "$sources_found" -ge "$max_sources" ]; then break; fi
        local other_article="${sorted_articles[$i]}"
        IFS='^' read -r o_score o_guid o_link o_title o_description <<< "$other_article"
        local match_count=0
        for keyword in "${primary_keywords[@]}"; do
            if echo "$o_title" | grep -iqF "$keyword"; then ((match_count++)); fi
        done
        if [ "$match_count" -ge 1 ]; then article_cluster+=("$other_article"); ((sources_found++)); fi
    done
    
    echo "Found $sources_found related article(s) for the topic: \"$p_title\""

    if [ "$debug_mode" = true ]; then
        echo -e "\n--- DEBUG OUTPUT: Clustered Articles ---"
        for article in "${article_cluster[@]}"; do
            IFS='^' read -r score guid link title description <<< "$article"
            echo "--------------------------------------------------"; echo "Title: $title"; echo "Link: $link"
        done
        exit 0
    fi

    echo -e "\nSTAGE 4: Generating synthesized article..."

    if generate_article_from_cluster "${article_cluster[@]}"; then
        for article in "${article_cluster[@]}"; do
            IFS='^' read -r _ guid _ _ _ <<< "$article"; echo "$guid" >> "$STATE_FILE"
        done
    else
        echo "Skipping article due to generation failure."
    fi

    echo -e "\nScan and generation complete."
}

main "$@"

