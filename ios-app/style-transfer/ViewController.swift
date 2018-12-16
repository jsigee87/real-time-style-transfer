import UIKit
import AVFoundation
import CoreML
import Accelerate

class ViewController: UIViewController , AVCaptureVideoDataOutputSampleBufferDelegate {
    
    //view capture stream
//    @IBOutlet fileprivate var capturePreviewView: UIView! (used for raw camera feed
    
    @IBOutlet weak var imageView: UIImageView!
    func loadSomeImage(img: UIImage) {
        self.imageView.image = img
    }

    // AVFoundation variable declarations
    var captureSession: AVCaptureSession?
    var rearCamera: AVCaptureDevice?
    var rearCameraInput: AVCaptureDeviceInput?
    var captureVideoOutput: AVCaptureVideoDataOutput?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var connection: AVCaptureConnection?
    
    // image processing variables (allocate once to avaid dynamic mem-alloc)
    var imageBuffer: CVPixelBuffer = createPixelBuffer(width: 1920, height: 1080)!
    var resizedPixelBuffer = createPixelBuffer(width: 480, height: 640)
    let context = CIContext()
    
    //ML Model
    var mlModelWrapper: green_swirly?
    var prediction: green_swirlyOutput?
    var input_to_model: green_swirlyInput?
    var options_cpu: MLPredictionOptions?
    
    
    #if DEBUG
        var frame_counter = 0
        var started_counting_frames = 0
        var start: CFAbsoluteTime = 0
    #endif
    
    override func viewDidLoad() {
        do {
            load_ml_model()
            createCaptureSession()
            try configureCaptureDevices()
            try configureDeviceInput()
            try configureCaptureOutput()
            try startCaptureSession()
        }
        catch {
            return
        }
    }
    
    func load_ml_model(){
        let bundle = Bundle(for: green_swirly.self)
        let modelURL = bundle.url(forResource: "green_swirly", withExtension:"mlmodelc")!
        mlModelWrapper = try? green_swirly(contentsOf: modelURL)
    }
    
    func createCaptureSession() {
        self.captureSession = AVCaptureSession()
    }
    
    /**
     This function configures the rear camera (if available) to capture video continuously
    */
    func configureCaptureDevices() throws {
        
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaType.video, position: .back)
        let cameras = session.devices.compactMap { $0 }
        guard !cameras.isEmpty else { throw camError.noCamerasAvailable }
        
        for camera in cameras {
            
            if camera.position == .back {
                self.rearCamera = camera
                
                //set configuration if allowed to do so
                try camera.lockForConfiguration()
                camera.focusMode = .continuousAutoFocus
                camera.unlockForConfiguration()
            }
        }
    }
    
    /**
     This function attaches the rear camera video feed as an input to the AV capture session
     (if a capture session is available).
    */
    func configureDeviceInput() throws {
        guard let captureSession = self.captureSession else { throw camError.captureSessionIsMissing }
        
        if let rearCamera = self.rearCamera {
            self.rearCameraInput = try AVCaptureDeviceInput(device: rearCamera)
            
            if captureSession.canAddInput(self.rearCameraInput!) { captureSession.addInput(self.rearCameraInput!) }
        }
        else { throw camError.noCamerasAvailable }
        
    }
    
    /**
     This function creates an output object from the AV session from which we can collect individual frames
     using the captureOutput() callback.
    */
    func configureCaptureOutput() throws {
        guard let captureSession = self.captureSession else { throw camError.captureSessionIsMissing }
        self.captureVideoOutput = AVCaptureVideoDataOutput()
        self.captureVideoOutput!.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sample buffer"))
        self.captureVideoOutput!.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA as UInt32]
        
        captureSession.sessionPreset = AVCaptureSession.Preset.vga640x480
        //captureSession.sessionPreset = AVCaptureSession.Preset.hd1920x1080
        
        if captureSession.canAddOutput(captureVideoOutput!) { captureSession.addOutput(captureVideoOutput!)}
    }
    
    /**
     This function begins the AV capture session
    */
    func startCaptureSession() throws {
        guard let captureSession = self.captureSession else { throw camError.captureSessionIsMissing }
        captureSession.startRunning()
    }
    
    /**
     This function is called every time the "sample buffer" dispatch queue is ready to output a frame.
     
     In this function we can grab a frame, perform operations on it (e.g. stylize the frame), then render
     to a UIImageView.
     
    */
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        var success: Bool = true
        
        //calculate frames per second by counting frames every second
        #if DEBUG
            if (started_counting_frames == 0){
                start = CFAbsoluteTimeGetCurrent()
                frame_counter = frame_counter + 1
                started_counting_frames = 1
            }
            else{
                let diff = CFAbsoluteTimeGetCurrent() - start
                if(diff < 1.0){
                    frame_counter = frame_counter + 1
                }
                else{
                    print("Frames per second = \(frame_counter) fps")
                    frame_counter = 0
                    started_counting_frames = 0
                }
            }
        #endif
        
        connection.videoOrientation = .portrait     //set frame orientation
        
        // Fetch CVPixelBuffer from "sample buffer" queue
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return  }
        
        // resize pixel buffer to 480x640 (width x height)
        /*
        #if DEBUG
            printTimeElapsedWhenRunningCode(title:"resizing buffer"){
                resizePixelBuffer(imageBuffer, width: 480, height: 640, output: resizedPixelBuffer!, context: context)
            }
        #else
            resizePixelBuffer(imageBuffer, width: 480, height: 640, output: resizedPixelBuffer!, context: context)
        #endif
        */
        
        // run input image through coreML .mlmodelc
        #if DEBUG
            printTimeElapsedWhenRunningCode(title:"prediction") {
                do {
                    // -- use CPU only --
                    /*
                    options_cpu = MLPredictionOptions()
                    options_cpu!.usesCPUOnly = true
                    
                    input_to_model = testInput(_0: resizedPixelBuffer!)
                    
                    prediction = try mlModelWrapper?.prediction(input: input_to_model!, options: options_cpu!)
                    */
                    
                    // use GPU
                    prediction = try mlModelWrapper?.prediction(_0: imageBuffer)
                }
                catch {
                    print("Camera warming up...")
                    success = false
                    return
                }
            }
        #else
            do {
                prediction = try mlModelWrapper?.prediction(_0: resizedPixelBuffer!)
            }
            catch {
                print("Camera warming up...")
                return
            }
        #endif
        
        if(!success) { return }
        
        #if DEBUG
            printTimeElapsedWhenRunningCode(title:"rendering image") {
                // code use to transform CVpixelbuffer into uiiview
                let ciImage = CIImage(cvPixelBuffer: (prediction?._156)!)
                guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return  }
                let image = UIImage(cgImage: cgImage)
                
                // Update imageView asynchronously using highest priority dispatch queue (.main)
                DispatchQueue.main.async{
                    self.loadSomeImage(img: image)
                }
            }
        #else
            // code use to transform CVpixelbuffer into uiiview
            let ciImage = CIImage(cvPixelBuffer: (prediction?._156)!)
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return  }
            let image = UIImage(cgImage: cgImage)
        
            // Update imageView asynchronously using highest priority dispatch queue (.main)
            DispatchQueue.main.async{
                self.loadSomeImage(img: image)
            }
        #endif
        
        
    }
    
    // enumerations for possible AVFoundation discovery and session errors
    enum camError: Swift.Error {
        case captureSessionAlreadyRunning
        case captureSessionIsMissing
        case inputsAreInvalid
        case invalidOperation
        case noCamerasAvailable
        case unknown
    }
    
    // helper function for benchmarking
    func printTimeElapsedWhenRunningCode(title:String, operation:()->()) {
        let startTime = CFAbsoluteTimeGetCurrent()
        operation()
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        print("Time elapsed for \(title): \(timeElapsed) s.")
    }
    
    // helper function for determining pixel format of CVPixelBuffer object
    public func CVPixelBufferGetPixelFormatName(pixelBuffer: CVPixelBuffer) -> String {
        let p = CVPixelBufferGetPixelFormatType(pixelBuffer)
        switch p {
        case kCVPixelFormatType_1Monochrome:                   return "kCVPixelFormatType_1Monochrome"
        case kCVPixelFormatType_2Indexed:                      return "kCVPixelFormatType_2Indexed"
        case kCVPixelFormatType_4Indexed:                      return "kCVPixelFormatType_4Indexed"
        case kCVPixelFormatType_8Indexed:                      return "kCVPixelFormatType_8Indexed"
        case kCVPixelFormatType_1IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_1IndexedGray_WhiteIsZero"
        case kCVPixelFormatType_2IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_2IndexedGray_WhiteIsZero"
        case kCVPixelFormatType_4IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_4IndexedGray_WhiteIsZero"
        case kCVPixelFormatType_8IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_8IndexedGray_WhiteIsZero"
        case kCVPixelFormatType_16BE555:                       return "kCVPixelFormatType_16BE555"
        case kCVPixelFormatType_16LE555:                       return "kCVPixelFormatType_16LE555"
        case kCVPixelFormatType_16LE5551:                      return "kCVPixelFormatType_16LE5551"
        case kCVPixelFormatType_16BE565:                       return "kCVPixelFormatType_16BE565"
        case kCVPixelFormatType_16LE565:                       return "kCVPixelFormatType_16LE565"
        case kCVPixelFormatType_24RGB:                         return "kCVPixelFormatType_24RGB"
        case kCVPixelFormatType_24BGR:                         return "kCVPixelFormatType_24BGR"
        case kCVPixelFormatType_32ARGB:                        return "kCVPixelFormatType_32ARGB"
        case kCVPixelFormatType_32BGRA:                        return "kCVPixelFormatType_32BGRA"
        case kCVPixelFormatType_32ABGR:                        return "kCVPixelFormatType_32ABGR"
        case kCVPixelFormatType_32RGBA:                        return "kCVPixelFormatType_32RGBA"
        case kCVPixelFormatType_64ARGB:                        return "kCVPixelFormatType_64ARGB"
        case kCVPixelFormatType_48RGB:                         return "kCVPixelFormatType_48RGB"
        case kCVPixelFormatType_32AlphaGray:                   return "kCVPixelFormatType_32AlphaGray"
        case kCVPixelFormatType_16Gray:                        return "kCVPixelFormatType_16Gray"
        case kCVPixelFormatType_30RGB:                         return "kCVPixelFormatType_30RGB"
        case kCVPixelFormatType_422YpCbCr8:                    return "kCVPixelFormatType_422YpCbCr8"
        case kCVPixelFormatType_4444YpCbCrA8:                  return "kCVPixelFormatType_4444YpCbCrA8"
        case kCVPixelFormatType_4444YpCbCrA8R:                 return "kCVPixelFormatType_4444YpCbCrA8R"
        case kCVPixelFormatType_4444AYpCbCr8:                  return "kCVPixelFormatType_4444AYpCbCr8"
        case kCVPixelFormatType_4444AYpCbCr16:                 return "kCVPixelFormatType_4444AYpCbCr16"
        case kCVPixelFormatType_444YpCbCr8:                    return "kCVPixelFormatType_444YpCbCr8"
        case kCVPixelFormatType_422YpCbCr16:                   return "kCVPixelFormatType_422YpCbCr16"
        case kCVPixelFormatType_422YpCbCr10:                   return "kCVPixelFormatType_422YpCbCr10"
        case kCVPixelFormatType_444YpCbCr10:                   return "kCVPixelFormatType_444YpCbCr10"
        case kCVPixelFormatType_420YpCbCr8Planar:              return "kCVPixelFormatType_420YpCbCr8Planar"
        case kCVPixelFormatType_420YpCbCr8PlanarFullRange:     return "kCVPixelFormatType_420YpCbCr8PlanarFullRange"
        case kCVPixelFormatType_422YpCbCr_4A_8BiPlanar:        return "kCVPixelFormatType_422YpCbCr_4A_8BiPlanar"
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:  return "kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange"
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:   return "kCVPixelFormatType_420YpCbCr8BiPlanarFullRange"
        case kCVPixelFormatType_422YpCbCr8_yuvs:               return "kCVPixelFormatType_422YpCbCr8_yuvs"
        case kCVPixelFormatType_422YpCbCr8FullRange:           return "kCVPixelFormatType_422YpCbCr8FullRange"
        case kCVPixelFormatType_OneComponent8:                 return "kCVPixelFormatType_OneComponent8"
        case kCVPixelFormatType_TwoComponent8:                 return "kCVPixelFormatType_TwoComponent8"
        case kCVPixelFormatType_30RGBLEPackedWideGamut:        return "kCVPixelFormatType_30RGBLEPackedWideGamut"
        case kCVPixelFormatType_OneComponent16Half:            return "kCVPixelFormatType_OneComponent16Half"
        case kCVPixelFormatType_OneComponent32Float:           return "kCVPixelFormatType_OneComponent32Float"
        case kCVPixelFormatType_TwoComponent16Half:            return "kCVPixelFormatType_TwoComponent16Half"
        case kCVPixelFormatType_TwoComponent32Float:           return "kCVPixelFormatType_TwoComponent32Float"
        case kCVPixelFormatType_64RGBAHalf:                    return "kCVPixelFormatType_64RGBAHalf"
        case kCVPixelFormatType_128RGBAFloat:                  return "kCVPixelFormatType_128RGBAFloat"
        case kCVPixelFormatType_14Bayer_GRBG:                  return "kCVPixelFormatType_14Bayer_GRBG"
        case kCVPixelFormatType_14Bayer_RGGB:                  return "kCVPixelFormatType_14Bayer_RGGB"
        case kCVPixelFormatType_14Bayer_BGGR:                  return "kCVPixelFormatType_14Bayer_BGGR"
        case kCVPixelFormatType_14Bayer_GBRG:                  return "kCVPixelFormatType_14Bayer_GBRG"
        default: return "UNKNOWN"
        }
    }
    

}


