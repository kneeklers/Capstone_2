"""
Convert YOLO PyTorch model to CoreML for iOS
Run this script to generate a .mlpackage file for Xcode
"""

from ultralytics import YOLO
import os

def convert_yolo_to_coreml():
    # Path to your trained model
    model_path = "best.pt"
    
    if not os.path.exists(model_path):
        print(f"❌ Model not found at {model_path}")
        print("   Make sure best.pt is in the same directory as this script")
        return
    
    print("🔄 Loading YOLO model...")
    model = YOLO(model_path)
    
    print("🔄 Converting to CoreML format...")
    print("   This may take a few minutes...")
    
    # Export to CoreML format
    # nms=True includes Non-Maximum Suppression in the model
    model.export(
        format="coreml",
        nms=True,
        imgsz=640,  # Input image size
    )
    
    print("\n✅ Conversion complete!")
    print("📁 Output file: best.mlpackage")
    print("\n📱 Next steps:")
    print("   1. Drag 'best.mlpackage' into your Xcode project")
    print("   2. Make sure 'Add to target: SerialNumberScanner' is checked")
    print("   3. Rebuild and run the app")

if __name__ == "__main__":
    convert_yolo_to_coreml()