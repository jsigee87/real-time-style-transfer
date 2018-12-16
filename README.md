# Neural Style Transfer of Live Video

<img src="https://imgur.com/pT3YfW8.gif"/>

---

## Introduction

This is a real time neural style transfer project for EE 461P Data Science Principles, at the University of Texas at Austin. The work here was created by [Kate Baumli](https://www.linkedin.com/in/katebaumli/), [Daniel Diamont](https://www.linkedin.com/in/daniel-diamont/), and [John Sigmon](https://www.linkedin.com/in/john-sigmon/). This is a public version of our work.

In making this project we used code from [PyTorch](https://github.com/pytorch/examples) and a [GitHub project](https://github.com/peterliht/knowledge-distillation-pytorch) on network compression.

This code is associated with the blog post [Real Time Video Neural Style Transfer](https://towardsdatascience.com/real-time-video-neural-style-transfer-9f6f84590832).

The models in this repository are currently not compressed versions. We plan to add these later.

---

## Contents

### iOS App

The `ios-app` folder contains an Xcode project that you can use to load the app onto your phone. You will have to adjust the build settings for the Apple Developer Certificate. The current settings are for an iPhone XR with iOS 12.1. If your settings are different you will need to adjust the target OS, and the Storyboard.
    
### Webcam App

The `webcam-app` folder contains an app that uses OpenCV and runs on Mac and Linux. It loads one of two saved PyTorch models (`green_swirly.pth` or `candy.pth`). The app loads your webcam feed (which must be configured as `/dev/video0`), stylizes it, and displays the output. You should be able to quit by pressing `q`. Sometimes it is cranky and needs to be manually killed. In this case run:

```bash
APP=$(ps | awk '/webcam_app.py/ {print $1}')
kill -9 "$APP"
```

To switch between the models, edit line 12 of the `webcam_app.py` file to say either 

```python
weights_fname = "candy.pth"
```

or

```python
weights_fname = "green_swirly.pth"
```
