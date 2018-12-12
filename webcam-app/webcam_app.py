#!/usr/bin/env python3
import os
import re
import numpy as np
from PIL import Image
import cv2
import torch
from torchvision import transforms
from model.transformer_net import TransformerNet

# Get paths and set vars
weights_fname = "candy.pth"
script_path = os.path.dirname(os.path.abspath(__file__))
path_to_weights = os.path.join(script_path, "model", weights_fname)
resolution = (640, 480)

# Change to GPU if desired
device = torch.device("cpu")

# Load PyTorch Model
model = TransformerNet()
with torch.no_grad():
   state_dict = torch.load(path_to_weights)
   for k in list(state_dict.keys()):
        if re.search(r'in\d+\.running_(mean|var)$', k):
            del state_dict[k]
   model.load_state_dict(state_dict)
   model.to(device)


# Get Webcam
cap = cv2.VideoCapture(0)
if not cap.isOpened():
    print("OpenCV cannot find your webcam! Check that it is under /dev/video0")
    exit(1)

while(True):
    # Grab frame and change to jpeg
    ret, frame = cap.read()
    cv2_im = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    pil_im = Image.fromarray(cv2_im)
    img = pil_im.resize(resolution)

    # Transforms to feed to network
    small_frame_tensor_transform = transforms.Compose([
        transforms.ToTensor(),
        transforms.Lambda(lambda x: x.mul(255))
    ])
    small_frame_tensor = small_frame_tensor_transform(img)
    small_frame_tensor = small_frame_tensor.unsqueeze(0).to(device)
    
    # Run inference and resize
    output = model(small_frame_tensor).cpu()
    styled = output[0]
    styled = styled.clone().clamp(0, 255).detach().numpy()
    styled = styled.transpose(1, 2, 0).astype("uint8")
    styled_resized = cv2.resize(styled ,(frame.shape[0], frame.shape[1]))

    # Display frame and break if user hits q
    cv2.imshow('frame', styled_resized)
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

# Cleanup
cap.release()
cv2.destroyAllWindows()
