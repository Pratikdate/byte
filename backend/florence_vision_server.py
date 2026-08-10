import os
import io
import base64
import logging
from flask import Flask, request, jsonify
from PIL import Image

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Model configuration parameters for Microsoft Florence-2-Base (232M)
MODEL_ID = "microsoft/Florence-2-base"
PARAM_COUNT = "232M"
DEFAULT_TASK = "<OCR_WITH_REGION>"
MAX_NEW_TOKENS = 1024
NUM_BEAMS = 3
DO_SAMPLE = False

processor = None
model = None
device = "cpu"

def load_florence_model():
    global processor, model, device
    try:
        import torch
        from transformers import AutoProcessor, AutoModelForCausalLM

        if torch.cuda.is_available():
            device = "cuda"
        elif hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            device = "mps"
        else:
            device = "cpu"

        logging.info(f"Loading {MODEL_ID} ({PARAM_COUNT} params) on device: {device}...")
        
        processor = AutoProcessor.from_pretrained(MODEL_ID, trust_remote_code=True)
        torch_dtype = torch.float16 if device in ["cuda", "mps"] else torch.float32
        model = AutoModelForCausalLM.from_pretrained(
            MODEL_ID,
            torch_dtype=torch_dtype,
            trust_remote_code=True
        ).to(device)
        model.eval()
        logging.info(f"Successfully loaded {MODEL_ID} ({PARAM_COUNT} params)!")
        return True
    except Exception as e:
        logging.warning(f"Florence-2-Base model lazy-load deferred or unavailable: {e}")
        return False

@app.route('/health', methods=['GET'])
def health():
    return jsonify({
        "status": "ok",
        "model": MODEL_ID,
        "params": PARAM_COUNT,
        "device": device,
        "loaded": model is not None,
        "supported_tasks": [
            "<OCR_WITH_REGION>",
            "<OCR>",
            "<DETAILED_CAPTION>",
            "<MORE_DETAILED_CAPTION>",
            "<OD>",
            "<DENSE_REGION_CAPTION>"
        ],
        "parameters": {
            "max_new_tokens": MAX_NEW_TOKENS,
            "num_beams": NUM_BEAMS,
            "do_sample": DO_SAMPLE
        }
    }), 200

def parse_florence_output(parsed_output, task):
    """Formats raw Florence-2 model outputs into a meaningful visual context string for Byte's LLM prompt."""
    extracted_text = ""
    caption = ""
    regions = []

    if isinstance(parsed_output, dict):
        # Task <OCR_WITH_REGION> or <OCR>
        if task in ["<OCR_WITH_REGION>", "<OCR>"]:
            ocr_text = parsed_output.get(task, parsed_output.get("<OCR>", ""))
            if isinstance(ocr_text, str):
                extracted_text = ocr_text
            elif isinstance(ocr_text, dict):
                extracted_text = ocr_text.get("labels", "")
                if isinstance(extracted_text, list):
                    extracted_text = " ".join(extracted_text)

        # Task <DETAILED_CAPTION> or <MORE_DETAILED_CAPTION>
        if task in ["<DETAILED_CAPTION>", "<MORE_DETAILED_CAPTION>"]:
            caption = parsed_output.get(task, "")
            if not isinstance(caption, str):
                caption = str(caption)

        # Regions / OD
        if "<OD>" in parsed_output or "<DENSE_REGION_CAPTION>" in parsed_output:
            od_data = parsed_output.get("<OD>", parsed_output.get("<DENSE_REGION_CAPTION>", {}))
            if isinstance(od_data, dict):
                bboxes = od_data.get("bboxes", [])
                labels = od_data.get("labels", [])
                for bbox, label in zip(bboxes, labels):
                    regions.append({"bbox": bbox, "label": label})

    elif isinstance(parsed_output, str):
        extracted_text = parsed_output

    # Synthesize meaningful context for Byte
    context_parts = []
    if caption:
        context_parts.append(f"Screen Scene: {caption}")
    if extracted_text:
        # Filter high value code/error keywords
        lines = [line.strip() for line in extracted_text.split('\n') if line.strip()]
        error_lines = [l for l in lines if any(k in l.lowercased() for k in ["error", "fatal", "exception", "failed", "warning"])]
        code_lines = [l for l in lines if any(k in l for k in ["func ", "class ", "def ", "import ", "let ", "var ", "return"])]

        if error_lines:
            context_parts.append(f"Detected Screen Errors: '{'; '.join(error_lines[:2])}'")
        elif code_lines:
            context_parts.append(f"Active Code Context: '{'; '.join(code_lines[:2])}'")
        else:
            snippet = " ".join(lines[:3])
            context_parts.append(f"Screen Text: '{snippet[:120]}'")

    if regions:
        region_labels = list(set([r['label'] for r in regions if r.get('label')]))[:3]
        if region_labels:
            context_parts.append(f"UI Elements: {', '.join(region_labels)}")

    meaningful_context = " | ".join(context_parts) if context_parts else "Developer focused in active workspace window."
    return extracted_text, caption, regions, meaningful_context

@app.route('/read_vision', methods=['POST'])
def read_vision():
    global model, processor

    data = request.json or {}
    image_b64 = data.get('image', '')
    task = data.get('task', DEFAULT_TASK)

    if not image_b64:
        return jsonify({"error": "No image payload provided"}), 400

    try:
        image_bytes = base64.b64decode(image_b64)
        image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    except Exception as e:
        return jsonify({"error": f"Failed to decode image data: {e}"}), 400

    # Lazy-load model on first request if not loaded
    if model is None:
        success = load_florence_model()
        if not success:
            return jsonify({
                "status": "unavailable",
                "message": "Florence-2-Base model dependencies not installed. Falling back to Apple Vision.",
                "fallback": True
            }), 503

    try:
        import torch
        inputs = processor(text=task, images=image, return_tensors="pt").to(device)

        with torch.no_grad():
            generated_ids = model.generate(
                input_ids=inputs["input_ids"],
                pixel_values=inputs["pixel_values"],
                max_new_tokens=MAX_NEW_TOKENS,
                num_beams=NUM_BEAMS,
                do_sample=DO_SAMPLE
            )

        generated_text = processor.batch_decode(generated_ids, skip_special_tokens=False)[0]
        parsed_output = processor.post_process_generation(
            generated_text,
            task=task,
            image_size=(image.width, image.height)
        )

        extracted_text, caption, regions, meaningful_context = parse_florence_output(parsed_output, task)

        return jsonify({
            "status": "success",
            "model": MODEL_ID,
            "params": PARAM_COUNT,
            "task": task,
            "extracted_text": extracted_text,
            "caption": caption,
            "regions": regions,
            "meaningful_context": meaningful_context
        }), 200

    except Exception as e:
        logging.error(f"Inference error during Florence-2 reading: {e}")
        return jsonify({"error": str(e), "fallback": True}), 500

if __name__ == '__main__':
    print(f"Starting Microsoft Florence-2-Base ({PARAM_COUNT}) Vision Server on port 9005...")
    app.run(host='0.0.0.0', port=9005)
