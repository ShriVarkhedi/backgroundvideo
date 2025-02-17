#import "backgroundvideo.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>

@implementation backgroundvideo

@synthesize parentView, view, session, output, outputPath, isFinished, previewLayer;

#ifndef __IPHONE_3_0
@synthesize webView;
#endif

//no longer needed for cordova platform 4+
// -(CDVPlugin*) initWithWebView:(UIWebView*)theWebView
// {
//     self = (backgroundvideo*)[super initWithWebView:theWebView];
//     return self;
// }

#pragma mark -
#pragma mark backgroundvideo

- (void) start:(CDVInvokedUrlCommand *)command
{
    //stop the device from being able to sleep
    [UIApplication sharedApplication].idleTimerDisabled = YES;

    self.token = [command.arguments objectAtIndex:0];
    self.camera = [command.arguments objectAtIndex:1];
    bool shouldRecordAudio = [[command.arguments objectAtIndex:2] boolValue];

    //get rid of the old view (causes issues if the app is resumed)
    self.parentView = nil;

    //make the view
    CGRect viewRect = CGRectMake(
                                 1,
                                 1,
                                 self.webView.superview.frame.size.width,
                                 self.webView.superview.frame.size.height
                                 );
    self.parentView = [[UIView alloc] initWithFrame:viewRect];
    [self.webView.superview addSubview:self.parentView];

    self.parentView.backgroundColor = [UIColor clearColor];
    self.view = [[UIView alloc] initWithFrame: self.parentView.bounds];
    [self.parentView addSubview: view];
    view.alpha = 0.2f;
    self.parentView.userInteractionEnabled = NO;

    //camera stuff

    //Capture session
    session = [[AVCaptureSession alloc] init];
    [session setSessionPreset:AVCaptureSessionPresetLow];

    //Get the front camera and set the capture device
    AVCaptureDevice *inputDevice = [self getCamera: self.camera];


    //write the file
    outputPath = [self getFileName];
    NSURL *fileURI = [[NSURL alloc] initFileURLWithPath:outputPath];

    //capture device output
    CMTime maxDuration = CMTimeMakeWithSeconds(1800, 1);

    output = [[AVCaptureMovieFileOutput alloc]init];
    output.maxRecordedDuration = maxDuration;


    if ( [session canAddOutput:output])
        [session addOutput:output];

    if(shouldRecordAudio){
        
        //Capture audio input
        AVCaptureDevice *audioCaptureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
        AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioCaptureDevice error:nil];

        if ([session canAddInput:audioInput])
            [session addInput:audioInput];
    
    }


    //Capture device input
    AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:inputDevice error:nil];
    if ( [session canAddInput:deviceInput] )
        [session addInput:deviceInput];


    //preview view
    self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
    [self.previewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];

    CALayer *rootLayer = [[self view] layer];
    [rootLayer setMasksToBounds:YES];
    [self.previewLayer setFrame:CGRectMake(-70, 0, rootLayer.bounds.size.height, rootLayer.bounds.size.height)];
    [rootLayer insertSublayer:self.previewLayer atIndex:0];

    //go
    [session startRunning];
    [output startRecordingToOutputFileURL:fileURI recordingDelegate:self ];

    //return true to ensure callback fires
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)stop:(CDVInvokedUrlCommand *)command
{
    [output stopRecording];
    self.view.alpha = 0;
    NSString *exportPath;
    
    // MP4 Conversion using the AVFoundation Framework
        
        [self.commandDelegate runInBackground:^{

            // Create the asset url with the video file
        
            NSURL *videoURL = [[NSURL alloc] initFileURLWithPath:outputPath];
        
            AVURLAsset *avAsset = [AVURLAsset URLAssetWithURL:videoURL options:nil];
            NSArray *compatiblePresets = [AVAssetExportSession exportPresetsCompatibleWithAsset:avAsset];

            // Check if video is supported for conversion or not
            if ([compatiblePresets containsObject:AVAssetExportPresetMediumQuality]) {
                // Create Export session
                AVAssetExportSession *exportSession = [[AVAssetExportSession alloc]initWithAsset:avAsset presetName:AVAssetExportPresetMediumQuality];

                // Creating temp path to save the converted video
                
                // NSString* documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
                // use temp directory
                
                NSString* tempDirectory = NSTemporaryDirectory();
                
                NSString* myDocumentPath = [tempDirectory stringByAppendingPathComponent:@"capturedVideo.mp4"];
                NSURL *url = [[NSURL alloc] initFileURLWithPath:myDocumentPath];

                // Check if the file already exists then remove the previous file
                if ([[NSFileManager defaultManager]fileExistsAtPath:myDocumentPath]) {
                    [[NSFileManager defaultManager]removeItemAtPath:myDocumentPath error:nil];
                }
            
                NSLog(@"Creating export file: %@",myDocumentPath);
                
                exportSession.outputURL = url;
            
                // Set the output file format, etc.
                exportSession.outputFileType = AVFileTypeMPEG4;
                exportSession.shouldOptimizeForNetworkUse = YES;
            
                [exportSession exportAsynchronouslyWithCompletionHandler:^{
                
                    switch ([exportSession status])    {
                        case AVAssetExportSessionStatusFailed:
                            NSLog(@"Video export session failed");
                            
                            break;
                        case AVAssetExportSessionStatusCancelled:
                            NSLog(@"Video export canceled");
                           
                            break;
                        case AVAssetExportSessionStatusCompleted:
                            //Video conversion finished
                            NSLog(@"Video MPEG compression export successful!");
                            NSLog(@"Export Success %@",myDocumentPath);
                            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:myDocumentPath];
                            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                            break;
                       
                    }
                }];
            }
            else {
                NSLog(@"Video file not supported!");
            }
        }];

   
}


-(NSString*)getFileName
{
    int fileNameIncrementer = 1;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *libPath = [self getLibraryPath];

    NSString *tempPath = [[NSString alloc] initWithFormat:@"%@%@_%i%@", libPath, self.token, fileNameIncrementer, FileExtension];

    while ([fileManager fileExistsAtPath:tempPath]) {
        tempPath = [NSString stringWithFormat:@"%@%@_%i%@", libPath, self.token, fileNameIncrementer, FileExtension];
        fileNameIncrementer++;
    }

    return tempPath;
}

-(NSString*)getLibraryPath
{
    NSArray *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *library = [lib objectAtIndex:0];
    return [NSString stringWithFormat:@"%@/NoCloud/", library];
}

-(AVCaptureDevice *)getCamera: (NSString *)camera
{
    NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    AVCaptureDevice *captureDevice = nil;
    for (AVCaptureDevice *device in videoDevices)
    {
        if([camera caseInsensitiveCompare:@"front"] == NSOrderedSame)
        {
            if (device.position == AVCaptureDevicePositionFront )
            {
                captureDevice = device;
                break;
            }
        }
        else if ([camera caseInsensitiveCompare:@"BACK"] == NSOrderedSame)
        {
            if (device.position == AVCaptureDevicePositionBack )
            {
                captureDevice = device;
                break;
            }
        }
        else
        {
            //TODO: return cordova error
            NSLog(@"Coudn't find camera");
        }
    }
    return captureDevice;
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
}

@end
