# DermScan AI 🩺🤖

DermScan AI is an AI-powered mobile application for early skin lesion analysis.  
It allows users to upload or capture an image of a skin lesion and receive an instant prediction, confidence score, risk level, and guidance.

## 🚀 Features

- 📷 Upload image from camera or gallery
- 🤖 AI-based skin disease classification
- 🧠 Supports 7 lesion categories
- 📊 Confidence score for predictions
- 🗺️ HeatMap for trustability
- ⚠️ Risk level assessment (High / Medium / Low)
- 📄 Disease explanation, symptoms , recommendations & Precautions
- 📍 Find nearby dermatologists using Google Maps
- 🕘 Scan history saved locally
- 📱 Modern Flutter mobile UI

## 🧬 Supported Classes

- Melanoma
- Basal Cell Carcinoma
- Actinic Keratosis
- Benign Keratosis
- Dermatofibroma
- Melanocytic Nevus
- Vascular Lesion

## 🛠️ Tech Stack

### Frontend
- Flutter
- Dart

### Backend
- Python
- Flask

### AI / ML
- PyTorch
- EfficientNetB0 (Transfer Learning)
- Grad-Cam
- OpenCV
- NumPy

### Storage
- SharedPreferences

## ⚙️ How It Works

1. User selects or captures an image
2. Flutter app sends image to Flask backend
3. Backend preprocesses image
4. EfficientNetB0 model predicts lesion type
5. Backend returns:
   - Disease name
   - Confidence score
   - Risk level
   - Medical guidance
6. Flutter displays results beautifully

## 📈 Model Performance

- Accuracy achieved: ~98% 
- Optimized using transfer learning

## ⚠️ Disclaimer

This project is for educational and prototype purposes only.  
It is **not a replacement for professional medical diagnosis**.

## 🔮 Future Improvements

- Cloud deployment
- Telemedicine integration
- Real-time camera scanning
- Multi-language support

## 👨‍💻 Author

Aditya Bhagat