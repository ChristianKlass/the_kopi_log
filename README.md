# The Kopi Log - An Automated AI Tech Blog
This repository contains the full pipeline for "The Kopi Log," an experimental and fully automated tech analysis blog. The entire system, from content sourcing and AI-driven synthesis to deployment, is designed to run unattended.

The live blog can be viewed at: https://thekopilog.markklass.dev

## What it Does
This project automatically scans multiple tech and gaming news feeds, identifies significant topics, and uses generative AI to write and publish unique analysis articles. It also includes a feature to detect and announce upcoming local and international events. The result is a self-sustaining blog that provides timely, AI-generated commentary.

## How it Works
The pipeline is orchestrated by a master Bash script (deploy.sh) which is typically run on a schedule (e.g., via cron). The process is as follows:

1. **Content Sourcing**: The script fetches the latest articles from a predefined list of RSS feeds.
2. **Event Detection**: It first scans for news about major upcoming events. If a new event is found, it generates a special announcement article and the script's run is complete. It will do this one time, so that the entire week isn't spammed with news about the event.
3. **Ranking & Clustering**: If no events are found, the script scores all regular news articles based on keywords. It then takes the top-ranked article and finds other related articles to form a "cluster" of sources on the same topic.
4. **AI Synthesis**: This cluster of sources is sent to the Google Gemini API. The AI is prompted to act as a tech analyst, synthesizing the information and writing a unique commentary with a local perspective.
5. **Image Generation**: A prompt based on the article's title is sent to the Google Imagen API to generate a unique cover image for the post. (this part requires payment, which I didn't, so it's currently untested.)
6. **Deployment**: The script uses docker compose to trigger a multi-stage Dockerfile. This process builds the Hugo static site, packages it into a lightweight Nginx container, and deploys it.
7. **Secure Exposure**: The live site is made publicly accessible using a secure Cloudflare Tunnel, requiring no open inbound ports on the host server.
---
## Setup Instructions
To get this project running, follow these steps:
1. Prerequisites:
    1. Docker & Docker Compose
    2. Git
    3. A Google Cloud Platform account with the Gemini and Imagen APIs enabled.
    4. A Cloudflare account for the tunnel.
2. Clone the Repository:
    1. `git clone https://github.com/ChristianKlass/the_kopi_log.git`
    2. `cd the_kopi_log`
3. Configure Environment Variables:
    1. Create a .env file in the project root. You can copy the example file to get started: `cp .env.example .env`
    2. Now, edit the .env file and fill in the following values:
    ```env
    GOOGLE_API_KEY='w6X9%5R*AW1P6zdzEpWU3@i5eNXvz4*cN3%nc$Y' # (this is fake don't bother using it)
    TUNNEL_TOKEN='aGi%l%@N8y0pCGw%jBi50grNfprN0iB3zaP9UUHjejL8r7sCt7cD%0yr8BHb2Xe!gtD5W6^QDzoE#7KiD*TJXY^zm@7fv$jjYKfb^n636' # (this is also fake)
    HUGO_SERVICES_GOOGLEANALYTICS_ID=G-8y8nb22HZt # (this one is real. lol obviously it's also fake)
    HUGO_PARAMS_AUTHOR=WhateverNameYouWant
    ```
4. Deploy:
    1. Run the deployment script. This will generate the first article and launch the Docker containers.
      ```shell
      ./deploy.sh
      # The first run may take a few minutes as Docker downloads the necessary images.
      ```

---

## Customizing the Blog's Focus
You can easily adapt the blog to cover any topic by changing the keywords and feeds in the `generate_article.sh` script.

### Change the RSS Feeds:
Modify the `RSS_FEEDS` array to include the RSS feeds for the topics you're interested in.

### Change the Keywords:
The script uses three arrays to score and identify content:
1. `HIGH_VALUE_KEYWORDS`: Words that are highly relevant to your niche. Articles containing these get a high score.
2. `LOW_VALUE_KEYWORDS`: General terms that are relevant but less important.
3. `EVENT_KEYWORDS`: Specific names of events you want the "Event Watcher" to look for.

### Change the AI Persona:
To change the writing style, edit the `prompt_template` variable inside the `generate_article_from_cluster` function. You can instruct the AI to adopt any persona or tone you wish.

---