import torch
import torch.nn as nn
from torchvision import transforms, models
from PIL import Image
from flask import Flask, request, jsonify
import cv2
import numpy as np
import base64
from io import BytesIO

app = Flask(__name__)

# ================= LOAD MODEL =================
# Changed from MobileNetV2 to EfficientNetB0
model = models.efficientnet_b0(weights=None)
model.classifier[1] = nn.Linear(model.classifier[1].in_features, 7)
model.load_state_dict(torch.load("best_fast_skin_model.pth", map_location="cpu"))
model.eval()

# ================= CLASSES =================
class_names = [
    "Melanoma",
    "Melanocytic Nevus",
    "Basal Cell Carcinoma",
    "Actinic Keratosis",
    "Benign Keratosis",
    "Dermatofibroma",
    "Vascular Lesion"
]

risk_map = {
    "Melanoma": "High",
    "Melanocytic Nevus": "Low",
    "Basal Cell Carcinoma": "Medium",
    "Actinic Keratosis": "Medium",
    "Benign Keratosis": "Low",
    "Dermatofibroma": "Low",
    "Vascular Lesion": "Low"
}

disease_info = {
    "Melanoma": {
        "description": "A dangerous type of skin cancer that develops from pigment-producing cells.",
        "symptoms": "Irregular borders, uneven color, asymmetry, rapid growth.",
        "advice": "⚠️ Urgent dermatologist consultation required.",
        "precautions": "• Avoid direct sun exposure\n• Use SPF 50+ sunscreen daily\n• Wear protective clothing\n• Avoid tanning beds\n• Monitor all moles regularly\n• Schedule monthly skin self-exams"
    },
    "Melanocytic Nevus": {
        "description": "A common mole, usually benign and non-cancerous.",
        "symptoms": "Round shape, uniform color, stable size.",
        "advice": "Generally harmless, but monitor for changes.",
        "precautions": "• Protect from excessive sun exposure\n• Use sunscreen on moles\n• Monitor for changes in size, shape, or color\n• Avoid picking or scratching\n• Annual dermatologist check-up recommended"
    },
    "Basal Cell Carcinoma": {
        "description": "A slow-growing skin cancer that rarely spreads but needs treatment.",
        "symptoms": "Pearly bump, bleeding sore, shiny patch.",
        "advice": "Consult a dermatologist for removal.",
        "precautions": "• Limit sun exposure, especially 10am-4pm\n• Apply broad-spectrum SPF 50+ sunscreen\n• Wear wide-brimmed hats\n• Seek shade when outdoors\n• Avoid tanning beds completely\n• Regular skin examinations"
    },
    "Actinic Keratosis": {
        "description": "A rough, scaly patch caused by sun damage; can become cancerous.",
        "symptoms": "Dry, crusty, or scaly skin patches.",
        "advice": "Early treatment recommended to prevent cancer.",
        "precautions": "• Minimize sun exposure\n• Use SPF 50+ sunscreen daily\n• Wear protective clothing and hats\n• Avoid peak sun hours (10am-4pm)\n• Do not pick at scaly patches\n• Follow up with dermatologist regularly"
    },
    "Benign Keratosis": {
        "description": "A non-cancerous skin growth, often age-related.",
        "symptoms": "Waxy, rough, or wart-like appearance.",
        "advice": "Usually harmless, no treatment needed unless irritated.",
        "precautions": "• Protect from sun exposure\n• Use sunscreen daily\n• Avoid scratching or picking\n• Wear loose clothing to prevent irritation\n• Monitor for changes in appearance\n• Consult if it becomes painful or bleeds"
    },
    "Dermatofibroma": {
        "description": "A benign skin nodule caused by minor injury or insect bite.",
        "symptoms": "Firm lump, usually brown or reddish.",
        "advice": "Harmless, treatment not required unless painful.",
        "precautions": "• Avoid trauma to the area\n• Do not squeeze or pick at it\n• Protect from sun exposure\n• Wear sunscreen on the area\n• Monitor for rapid growth\n• See doctor if it becomes painful"
    },
    "Vascular Lesion": {
        "description": "A skin condition caused by abnormal blood vessels.",
        "symptoms": "Red, purple, or blue discoloration on skin.",
        "advice": "Generally harmless but consult if it changes.",
        "precautions": "• Protect from sun exposure\n• Use gentle skincare products\n• Avoid harsh chemicals on the area\n• Do not scratch or irritate\n• Monitor for bleeding or changes\n• Avoid extreme temperatures on the area"
    }
}


# ================= TRANSFORM =================
# Input size remains 224x224 (same as MobileNetV2)
transform = transforms.Compose([
    transforms.Resize((224, 224)),
    transforms.ToTensor(),
])

# ================= GRAD-CAM HELPER =================
class GradCAM:
    def __init__(self, model, target_layer):
        self.model = model
        self.target_layer = target_layer
        self.gradients = None
        self.activations = None
        self.hooks = []

    def _forward_hook(self, module, input, output):
        self.activations = output

    def _backward_hook(self, module, grad_input, grad_output):
        self.gradients = grad_output[0]

    def generate(self, input_tensor, class_idx):
        self.hooks.append(self.target_layer.register_forward_hook(self._forward_hook))
        self.hooks.append(self.target_layer.register_full_backward_hook(self._backward_hook))

        self.model.zero_grad()
        output = self.model(input_tensor)
        score = output[0, class_idx]
        score.backward()

        pooled_grads = torch.mean(self.gradients, dim=(0, 2, 3))
        activations = self.activations[0]
        
        num_channels = activations.shape[0]
        heatmap = torch.zeros(activations.shape[1:])
        
        for i in range(num_channels):
            heatmap += pooled_grads[i] * activations[i]

        heatmap = torch.relu(heatmap)
        if torch.max(heatmap) > 0:
            heatmap /= torch.max(heatmap)
        
        heatmap = heatmap.detach().cpu().numpy()
        heatmap = cv2.resize(heatmap, (224, 224))
        heatmap = np.uint8(255 * heatmap)
        heatmap = cv2.applyColorMap(heatmap, cv2.COLORMAP_JET)

        for hook in self.hooks:
            hook.remove()
            
        return heatmap

# Changed target layer for EfficientNetB0
grad_cam = GradCAM(model, model.features[-1])

def encode_image_to_base64(image_obj):
    buffered = BytesIO()
    image_obj.save(buffered, format="PNG")
    return base64.b64encode(buffered.getvalue()).decode("utf-8")

# ================= API =================
@app.route('/predict', methods=['POST'])
def predict():
    try:
        file = request.files['image']
        image = Image.open(file).convert('RGB')
        original_image = image.copy()

        image_tensor = transform(image).unsqueeze(0)

        with torch.no_grad():
            outputs = model(image_tensor)
            probs = torch.softmax(outputs, dim=1)
            confidence, predicted = torch.max(probs, 1)

        predicted_class = predicted.item()
        confidence_percent = confidence.item() * 100
        disease = class_names[predicted_class]
        risk = risk_map.get(disease, "Unknown")
        info = disease_info.get(disease)

        heatmap_img = None
        if confidence_percent > 30:
            with torch.set_grad_enabled(True):
                heatmap = grad_cam.generate(image_tensor, predicted_class)
            
            original_resized = cv2.cvtColor(np.array(original_image.resize((224, 224))), cv2.COLOR_RGB2BGR)
            blended = cv2.addWeighted(original_resized, 0.6, heatmap, 0.4, 0)
            blended_rgb = cv2.cvtColor(blended, cv2.COLOR_BGR2RGB)
            heatmap_pil = Image.fromarray(blended_rgb)
            heatmap_img = encode_image_to_base64(heatmap_pil)

        print("Predicted:", predicted_class)
        return jsonify({
            "disease": disease,
            "confidence": confidence_percent,
            "risk": risk if confidence_percent > 60 else "Uncertain",
            "description": info["description"],
            "symptoms": info["symptoms"],
            "advice": info["advice"],
            "precautions": info["precautions"],  # ← ADDED THIS LINE
            "warning": "⚠️ AI is not very confident. Please consult a doctor." if confidence_percent < 60 else "",
            "heatmap": heatmap_img
        })
    except Exception as e:
        print("Error:", str(e))
        return jsonify({"error": str(e)}), 500


# ================= RUN =================
if __name__ == '__main__':
    app.run(debug=True)
