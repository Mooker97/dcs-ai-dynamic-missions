# ElevenLabs image generation

`elevenlabs_image.py` generates one image through ElevenLabs Image & Video
(`POST /v1/flows/image`, then poll `GET /v1/flows/image/{id}`, then download `content_url`).
It uses only the Python standard library.

## Requirements

- An ElevenLabs **Pro plan or above**. API image generation needs Pro.
- `ELEVENLABS_API_KEY` in the environment or in `DMS/.env`, with the
  **`image_video_generation`** permission (the dashboard calls it "Image & Video").
  Add **`user_read`** too if you want the tool to report the credits each image used.
- ByteDance models are disabled for API use until ElevenLabs approves them.

## Usage

```bash
uv run python tools/image_gen/elevenlabs_image.py \
  --prompt "Two A-10s over a desert valley at dusk, painted briefing art" \
  --out campaigns/<slug>/missions/<id>/briefing.png \
  --model gemini-3.1-flash-image --aspect 4:3 --resolution 1K
```

Options: `--model` (default `gemini-3.1-flash-lite-image`), `--aspect` (e.g. `1:1`, `4:3`,
`16:9`), `--resolution` (`512`/`1K`/`2K`/`4K`, depending on the model), `--quality`
(`low`/`medium`/`high`, gpt-image models only) and `--seed` (seedream only). Each model accepts
only its own fields, so the API rejects an option the model doesn't support.

The models available as of SDK 2.75 are `gemini-3.1-flash-lite-image`, `gemini-3.1-flash-image`,
`gemini-2.5-flash-image`, `gemini-3-pro-image`, `gpt-image-1`, `gpt-image-1.5`, `gpt-image-2`,
`gpt-image-2.5-sunburst`, `gpt-image-2.5-flare`, `bytedance-seedream-5-lite` and
`bytedance-seedream-5-pro`.

The response doesn't include a cost. The ElevenLabs app shows the price before you submit.
Failed generations aren't charged.

The builder embeds `campaigns/<slug>/missions/<id>/briefing.png` (or `.jpg`) as the
mission briefing picture.

Docs: https://elevenlabs.io/docs/eleven-api/guides/cookbooks/image-and-video ,
https://elevenlabs.io/docs/api-reference/flows/image/create
