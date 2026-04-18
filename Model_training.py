# ==========================================================
# MAX SPEED RTX 3050 VERSION (HAM10000)
# EfficientNet-B0 (Much Faster than B3)
# High Accuracy + Fast Training + Mixed Precision
# Resume Training + ETA + Metrics
# ==========================================================

import os
import time
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim

from torchvision import datasets, transforms, models
from torch.utils.data import DataLoader
from sklearn.metrics import classification_report, confusion_matrix
from sklearn.utils.class_weight import compute_class_weight
from tqdm import tqdm

# ==========================================================
# WINDOWS SAFE
# ==========================================================

if __name__ == "__main__":

    torch.backends.cudnn.benchmark = True

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    print("Using Device:", device)
    if torch.cuda.is_available():
        print("GPU:", torch.cuda.get_device_name(0))

    # ======================================================
    # SETTINGS
    # ======================================================

    DATASET_PATH = "dataset"
    IMG_SIZE = 224
    BATCH_SIZE = 64          # RTX3050 optimized
    EPOCHS = 18
    LR = 5e-4
    NUM_WORKERS = 2
    MODEL_PATH = "best_fast_skin_model.pth"

    # ======================================================
    # FAST TRANSFORMS
    # ======================================================

    train_tfms = transforms.Compose([
        transforms.Resize((IMG_SIZE, IMG_SIZE)),
        transforms.RandomHorizontalFlip(),
        transforms.RandomRotation(10),
        transforms.ToTensor(),
        transforms.Normalize([0.485,0.456,0.406],
                             [0.229,0.224,0.225])
    ])

    val_tfms = transforms.Compose([
        transforms.Resize((IMG_SIZE, IMG_SIZE)),
        transforms.ToTensor(),
        transforms.Normalize([0.485,0.456,0.406],
                             [0.229,0.224,0.225])
    ])

    # ======================================================
    # DATASET
    # ======================================================

    train_ds = datasets.ImageFolder(
        os.path.join(DATASET_PATH, "train"),
        transform=train_tfms
    )

    val_ds = datasets.ImageFolder(
        os.path.join(DATASET_PATH, "val"),
        transform=val_tfms
    )

    train_loader = DataLoader(
        train_ds,
        batch_size=BATCH_SIZE,
        shuffle=True,
        num_workers=NUM_WORKERS,
        pin_memory=True
    )

    val_loader = DataLoader(
        val_ds,
        batch_size=BATCH_SIZE,
        shuffle=False,
        num_workers=NUM_WORKERS,
        pin_memory=True
    )

    class_names = train_ds.classes
    num_classes = len(class_names)

    print("Classes:", class_names)

    # ======================================================
    # CLASS WEIGHTS
    # ======================================================

    labels = train_ds.targets

    weights = compute_class_weight(
        class_weight="balanced",
        classes=np.unique(labels),
        y=labels
    )

    class_weights = torch.tensor(weights, dtype=torch.float).to(device)

    # ======================================================
    # MODEL (FASTEST GOOD OPTION)
    # ======================================================

    model = models.efficientnet_b0(weights="DEFAULT")

    in_features = model.classifier[1].in_features

    model.classifier = nn.Sequential(
        nn.Dropout(0.25),
        nn.Linear(in_features, num_classes)
    )

    model = model.to(device)

    # ======================================================
    # LOSS + OPTIMIZER
    # ======================================================

    criterion = nn.CrossEntropyLoss(weight=class_weights)

    optimizer = optim.AdamW(model.parameters(), lr=LR)

    scheduler = optim.lr_scheduler.ReduceLROnPlateau(
        optimizer,
        mode="max",
        factor=0.5,
        patience=2
    )

    scaler = torch.amp.GradScaler("cuda")

    # ======================================================
    # RESUME IF MODEL EXISTS
    # ======================================================

    best_acc = 0

    if os.path.exists(MODEL_PATH):
        model.load_state_dict(torch.load(MODEL_PATH))
        print("Loaded previous best model.")

    # ======================================================
    # TRAINING
    # ======================================================

    for epoch in range(EPOCHS):

        start = time.time()

        model.train()

        total = 0
        correct = 0
        running_loss = 0

        loop = tqdm(train_loader, desc=f"Epoch {epoch+1}/{EPOCHS}")

        for images, labels in loop:

            images = images.to(device, non_blocking=True)
            labels = labels.to(device, non_blocking=True)

            optimizer.zero_grad()

            with torch.amp.autocast("cuda"):

                outputs = model(images)
                loss = criterion(outputs, labels)

            scaler.scale(loss).backward()
            scaler.step(optimizer)
            scaler.update()

            running_loss += loss.item()

            _, preds = torch.max(outputs, 1)

            total += labels.size(0)
            correct += (preds == labels).sum().item()

            acc = 100 * correct / total

            loop.set_postfix(
                loss=f"{loss.item():.4f}",
                acc=f"{acc:.2f}%"
            )

        train_acc = 100 * correct / total

        # ==================================================
        # VALIDATION
        # ==================================================

        model.eval()

        val_total = 0
        val_correct = 0

        all_preds = []
        all_labels = []

        with torch.no_grad():

            for images, labels in val_loader:

                images = images.to(device)
                labels = labels.to(device)

                with torch.amp.autocast("cuda"):
                    outputs = model(images)

                _, preds = torch.max(outputs, 1)

                val_total += labels.size(0)
                val_correct += (preds == labels).sum().item()

                all_preds.extend(preds.cpu().numpy())
                all_labels.extend(labels.cpu().numpy())

        val_acc = 100 * val_correct / val_total

        scheduler.step(val_acc)

        sec = time.time() - start

        print(f"\nTrain Acc : {train_acc:.2f}%")
        print(f"Val Acc   : {val_acc:.2f}%")
        print(f"Time/Epoch: {sec:.1f} sec")

        if torch.cuda.is_available():
            mem = torch.cuda.memory_allocated()/1024**3
            print(f"GPU Used: {mem:.2f} GB")

        if val_acc > best_acc:
            best_acc = val_acc
            torch.save(model.state_dict(), MODEL_PATH)
            print("Best model saved!")

    # ======================================================
    # FINAL REPORT
    # ======================================================

    print("\nLoading Best Model...")
    model.load_state_dict(torch.load(MODEL_PATH))
    model.eval()

    print("\n==============================")
    print("FINAL REPORT")
    print("==============================")
    print(f"Best Accuracy: {best_acc:.2f}%\n")

    print(classification_report(
        all_labels,
        all_preds,
        target_names=class_names,
        digits=4
    ))

    print("Confusion Matrix:\n")
    print(confusion_matrix(all_labels, all_preds))