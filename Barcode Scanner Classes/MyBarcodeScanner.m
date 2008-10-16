//
//  MyBarcodeScanner.m


#import "MyBarcodeScanner.h"
#import "MyiSightWindow.h"
#import "MyGraphView.h"

//#import <Carbon/Carbon.h>  //included from quicktime
#import <QuickTime/QuickTimeComponents.h>
#define TARGET_API_MAC_CARBON 1

//Not digit found value
#define NOT_FOUND -1
//How many bytes per pixel
#define SAMPLES_PER_PIXEL 4
//The multiple of the average spacing that defines that a barcode area is over
#define MULTIPLY_AVERAGE_SPACING 4.0 
//Number of lines to scan
#define NUMBER_OF_LINES_SCANNED 6
//Pixels between lines
#define SPACING_BETWEEN_SCAN_LINE 2
//offset of each center point on each line, starts in horizontal center.
#define SPACING_BETWEEN_CENTERS 2
//At what value of the (read width / ideal single bar width) is a bar considered 4 bars wide.
#define SEPARATION_VALUE_FOR_3_BARS 3.7
//the roof limit of how sure ofa  digit value the algorythm can be. The lower the number the more volatile 
#define SURENESS_LIMIT 10
//At what row to start scanning
#define FIRST_LINE_SCAN (240 - (NUMBER_OF_LINES_SCANNED /2 * SPACING_BETWEEN_SCAN_LINE))
//What to set the focus of the external iSights to
#define CAMERA_FOCUS 0.35
//Same as NSLog but stays in a shipping program, as serious errors to log to the console.
#define DLog NSLog
// Minimum number of digits that need to be scan in one pass to consider the number worthy of adding to information present
#define MINIMUM_DIGITS_FOR_GOOD_SCAN 8


//EAN encoding type
enum {
	MKLeftHandEncodingOdd,
	MKLeftHandEncodingBoth,
	MKRightHandEncoding
};



@interface MyBarcodeScanner (Private)

- (void)processPixelBuffer;  //This is the function called to scan the barcode
- (void)foundBarcode:(NSString *)aBarcode;  //Let the program know a barcode was found
- (void)idleTimer;  //The timer ffor the seqquenceGrabber and to scan for a barcode  ~33 frames/per second

//All these are for decoding the barcode 
- (void)clear:(id)sender;
- (void)findStart:(int *)startBarcode end:(int *)endBarcode forLine:(int *)pixelLineArray derivative:(int *)lineDerivativeArray centerAt:(int)centerX min:(int *)minValue max:(int *)maxValue;
- (void)getBars:(int [62])barsArrayOneDimension forLine:(int *)pixelLineArray derivative:(int *)lineDerivativeArray start:(int)startBarcode end:(int)endBarcode top:(int)topMask bottom:(int)bottomMask;
- (BOOL)getBinaryValueForPixel:(int)pixelValue derivativeForPixel:(int)derivative top:(int)topMask bottom:(int)bottomMask;
- (void)readBars:(int [62])lastBinaryData;
- (BOOL)compareAgainstPreviousScans:(char [3][12])aNumberArray previous:(char [3][12])previousNumberArray;
- (BOOL)checkCheckDigit:(char [3][12])aNumberArray;
- (void)getGreenFromRGB:(Ptr)rowPointer to:(int *)anArray640;
- (void)getNumberForLocation:(int *)anArray  encoding:(int)encodingType location:(int)numberIndex;
- (NSString *)stringFromArrray:(char [3][12])aNumberArray;
- (NSString *)barcodeFromArray:(char [3][12])aNumberArray;
int getNumberStripesEAN(int number, double average);

//Experimental
#if DEBUG
- (void)getPeakDistance:(int [62])barsArrayOneDimension forLine:(int *)pixelLineArray start:(int)startBarcode end:(int)endBarcode;
	//ComponentResult ConfigureGain(SGChannel inChannel);
#endif DEBUG


@end


// mung data struct
typedef struct {
    WindowRef        	pWindow;	// window
    Rect 				boundsRect;	// bounds rect
    GWorldPtr 		 	pGWorld;	// offscreen
    SeqGrabComponent 	seqGrab;	// sequence grabber
    ImageSequence 	 	decomSeq;	// unique identifier for our decompression sequence
    ImageSequence 	 	drawSeq;	// unique identifier for our draw sequence
    long 			 	drawSize;
    TimeValue 		 	lastTime;
    TimeScale 		 	timeScale;
    long 			 	frameCount;
} MungDataRecord, *MungDataPtr;


// globals
static MungDataPtr gMungData = NULL;
static BOOL mirrored = NO;  
BOOL foundBarcodeArea;
Ptr pixelBufferBaseAddress = NULL;
long bytesPerRow;
SeqGrabComponent seqGrab = NULL;
#if DEBUG
MyGraphView *graphView = nil;
#endif DEBUG


//sequence grabber functions
OSErr InitializeMungData(Rect inBounds, WindowRef inWindow);
SeqGrabComponent MakeSequenceGrabber(WindowRef pWindow);
OSErr MakeSequenceGrabChannel(SeqGrabComponent seqGrab, SGChannel *sgchanVideo, Rect const *rect);
OSErr MakeImageSequenceForGWorld(GWorldPtr pGWorld, GWorldPtr pDest, long *imageSize, ImageSequence *seq);
pascal OSErr MungGrabDataProc(SGChannel c, Ptr p, long len, long *offset, long chRefCon, TimeValue time, short writeType, long refCon);


#pragma mark -
@implementation MyBarcodeScanner

- (void)scanForBarcodeWindow:(NSWindow *)callingWindow {
	
	
	//iSight window is open and running return
	if (iSightWindow != nil && seqGrab!= NULL) {
		[iSightWindow makeKeyAndOrderFront:self];
		return;
	}
	
	
	// If we are in debug mode show a graph of the green pixel value
#if DEBUG
	NSWindow *graphWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(30,30,640,260) styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
	
	[graphWindow setLevel: NSNormalWindowLevel];
	[graphWindow setAlphaValue:1.00];
	[graphWindow setOpaque:YES];
	[graphWindow setHasShadow:NO];
	graphView = [[[MyGraphView alloc] initWithFrame:[[graphWindow contentView] bounds]] autorelease];
	[graphWindow setContentView:graphView];
	[graphWindow makeKeyAndOrderFront:self];
#endif DEBUG
		

	//create a window to show the iSight in
	NSRect screenFrame = [[NSScreen mainScreen] visibleFrame];
	iSightWindow = [[MyiSightWindow alloc] initWithContentRect:NSMakeRect(screenFrame.origin.x + 20,screenFrame.size.height - 520,640,480) styleMask:NSTitledWindowMask | NSClosableWindowMask backing:NSBackingStoreBuffered defer:NO];
	[iSightWindow setFrameAutosaveName:@"iSightWindow"];
	[iSightWindow setTitle:@"iSight"];
	[iSightWindow setDelegate:self];
	[iSightWindow setLevel: NSNormalWindowLevel];
	[iSightWindow setAlphaValue:1.00];
	[iSightWindow setOpaque:YES];
	[iSightWindow setHasShadow:YES];
	[iSightWindow makeKeyAndOrderFront:self];
	WindowRef pMainWindow = [iSightWindow windowRef];


	
	
    // initialize our data
	Rect portRect;
	GetPortBounds(GetWindowPort(pMainWindow), &portRect);
    OSErr err = InitializeMungData(portRect, pMainWindow);
	if (err)  {	[iSightWindow close]; return;}
    	
    // create and initialize the sequence grabber
    seqGrab = MakeSequenceGrabber(pMainWindow);
	if (seqGrab == NULL)  {	[iSightWindow close]; return;}
    
    // create the channel
	SGChannel sgchanVideo;    
    err = MakeSequenceGrabChannel(seqGrab, &sgchanVideo, &portRect);
	
	// Unable to find the isight return and tell the user
	if (err)  {
		DLog(@"Error: Can't connect to iSight: %d", err);
		[iSightWindow close];
		
		//If it was called from a window display the alert in a sheet
		if (callingWindow)
			NSBeginAlertSheet([[NSBundle mainBundle] localizedStringForKey:@"Action Required" value:@"Action Required" table:@"MainTranslation"], @"OK", nil, nil, callingWindow, nil, nil, nil, nil, [[NSBundle mainBundle] localizedStringForKey:@"No iSight" value:@"Please make sure your firewire camera is connected to your computer." table:@"MainTranslation"]);
		else {
			NSRunAlertPanel([[NSBundle mainBundle] localizedStringForKey:@"Action Required" value:@"Action Required" table:@"MainTranslation"], [[NSBundle mainBundle] localizedStringForKey:@"No iSight" value:@"Please make sure your firewire camera is connected to your computer." table:@"MainTranslation"], @"OK", nil, nil);
		}
	}
	else {
	

		//Try to set the saturation 
		// doesn't give an error but nothing happens
		/*
		ComponentInstance videoComponent = SGGetVideoDigitizerComponent(sgchanVideo);
		unsigned short saturation = 0;
		VideoDigitizerError error = VDGetSaturation(videoComponent, &saturation);
		NSLog(@"Error: %d ", error);
		 */
		

		
		
		// Set the focus value helps with external iSights
		// Thanks to Wil Shipley for the focus code: http://lists.apple.com/archives/quicktime-api/2004/Mar/msg00257.html
		long quickTimeVersion = 0;
		if (Gestalt(gestaltQuickTime, &quickTimeVersion) || ((quickTimeVersion & 0xFFFFFF00) > 0x0708000)) {
			QTAtomContainer iidcFeaturesAtomContainer = NULL;
			QTAtom featureAtom = nil;
			QTAtom typeAndIDAtom = nil;
			QTAtom featureSettingsAtom = nil;
			QTNewAtomContainer(&iidcFeaturesAtomContainer);
			
			
			QTInsertChild(iidcFeaturesAtomContainer, kParentAtomIsContainer, vdIIDCAtomTypeFeature, 1, 0, 0, nil, &featureAtom);
			VDIIDCFeatureAtomTypeAndID featureAtomTypeAndID = {vdIIDCFeatureFocus, vdIIDCGroupMechanics, {5}, vdIIDCAtomTypeFeatureSettings, vdIIDCAtomIDFeatureSettings};
			QTInsertChild(iidcFeaturesAtomContainer, featureAtom, vdIIDCAtomTypeFeatureAtomTypeAndID, vdIIDCAtomIDFeatureAtomTypeAndID, 0, sizeof(featureAtomTypeAndID), &featureAtomTypeAndID, &typeAndIDAtom);
			VDIIDCFeatureSettings featureSettings = {{0, 0, 0, 0.0, 0.0}, {vdIIDCFeatureFlagOn | vdIIDCFeatureFlagManual | vdIIDCFeatureFlagRawControl, CAMERA_FOCUS}};
			QTInsertChild(iidcFeaturesAtomContainer, featureAtom, vdIIDCAtomTypeFeatureSettings, vdIIDCAtomIDFeatureSettings, 0, sizeof(featureSettings), &featureSettings, &featureSettingsAtom);
			VDIIDCSetFeatures(SGGetVideoDigitizerComponent(sgchanVideo), iidcFeaturesAtomContainer);
		}
		

		
		//Set settings 
		//ComponentResult result = ConfigureGain(sgchanVideo);
		//NSLog(@"Gain: %d", result);
		
		
		
		
		// specify a data function
		err = SGSetDataProc(seqGrab, NewSGDataUPP(MungGrabDataProc), (long)self);
		if (err)  {	[iSightWindow close]; return;}
		
		// lights...camera...
		err = SGPrepare(seqGrab, false, true);
		if (err)  {	[iSightWindow close]; return;}
		
		// ...action
		err = SGStartRecord(seqGrab);
		if (err)  {	[iSightWindow close]; return;}
		
		
		//Prepare the info we going to use for barcode scanning
		[self clear:self];  //Clear the numbers array
		[lastBarcode release]; //release any previously scanned barcodes
		lastBarcode = nil;
		
		//Prepare the pixel buffer information
		PixMapHandle hPixMap = GetGWorldPixMap(gMungData->pGWorld); 
		pixelBufferBaseAddress = GetPixBaseAddr(hPixMap);
		bytesPerRow = QTGetPixMapHandleRowBytes(hPixMap);
		//numberOfPixelsInRow = (theRowBytes / 4)  - 4; 
		


		//we need to send an idle message in a loop to update the iSight view and scan for the barcode
		//Do scans at ~33 frames per second
		idleTimer = [NSTimer scheduledTimerWithTimeInterval:0.03 target:self selector:@selector(idleTimer) userInfo:nil repeats:YES];

	}
    
}

/*
 This doesn't work for the built in isight
ComponentResult ConfigureGain(SGChannel inChannel)
{
	QTAtomContainer         atomContainer;
	QTAtom                  featureAtom;
	VDIIDCFeatureSettings   settings;
	VideoDigitizerComponent vd;
	ComponentDescription    desc;
	ComponentResult         result = paramErr;
	
	if (NULL == inChannel) goto bail;
	
	// get the digitizer and make sure it's legit
	vd = SGGetVideoDigitizerComponent(inChannel);
	if (NULL == vd) goto bail;
	
	GetComponentInfo((Component)vd, &desc, NULL, NULL, NULL);
	//if (vdSubtypeIIDC != desc.componentSubType) goto bail;
	
	// Internal iSight returns usbv 
	if ('usbv' != desc.componentSubType) goto bail;

	// *** now do the real work ***
	
	// return the gain feature in an atom container
	result = VDIIDCGetFeaturesForSpecifier(vd, vdIIDCFeatureGain, &atomContainer);
	if (noErr == result) {
		
		// find the feature atom
		featureAtom = QTFindChildByIndex(atomContainer, kParentAtomIsContainer,
										 vdIIDCAtomTypeFeature, 1, NULL);
		if (0 == featureAtom) { result = cannotFindAtomErr; goto bail; }
		
		// find the gain settings from the feature atom and copy the data
		// into our settings
		result = QTCopyAtomDataToPtr(atomContainer,
									 QTFindChildByID(atomContainer, featureAtom,
													 vdIIDCAtomTypeFeatureSettings,
													 vdIIDCAtomIDFeatureSettings, NULL),
									 true, sizeof(settings), &settings, NULL);
		if (noErr == result) {
			/* When indicating capabilities, the flag being set indicates that the
			feature can be put into the given state.
			When indicating/setting state, the flag represents the current/desired
			state. Note that certain combinations of flags are valid for capabilities
			(i.e. vdIIDCFeatureFlagOn | vdIIDCFeatureFlagOff) but are mutually
			exclusive for state.
			*//*
			// is the setting supported?
			if (settings.capabilities.flags & (vdIIDCFeatureFlagOn |
											   vdIIDCFeatureFlagManual |
											   vdIIDCFeatureFlagRawControl)) {
				// set state flags
				settings.state.flags = (vdIIDCFeatureFlagOn |
										vdIIDCFeatureFlagManual |
										vdIIDCFeatureFlagRawControl);
				
				// set value - will either be 500 or the max value supported by
				// the camera represented in a float between 0 and 1.0
				settings.state.value = (1.0 / settings.capabilities.rawMaximum) *
					((settings.capabilities.rawMaximum > 500) ? 500 :
					 settings.capabilities.rawMaximum);
				
				// store the result back in the container
				result = QTSetAtomData(atomContainer,
									   QTFindChildByID(atomContainer, featureAtom,
													   vdIIDCAtomTypeFeatureSettings,
													   vdIIDCAtomIDFeatureSettings, NULL),
									   sizeof(settings), &settings);
				if (noErr == result) {
					// set it on the device
					result = VDIIDCSetFeatures(vd, atomContainer);
				}
			} else {
				// can't do it!
				result = featureUnsupported;
			}
		}
	}
	
bail:
		return result;
}
*/




//When the window closes it's time to close the iSight as well and the timer
- (void)windowWillClose:(NSNotification *)aNotification {
		
	[idleTimer invalidate];
	idleTimer = nil;
	
	if (seqGrab) {
		SGStop(seqGrab);
		CloseComponent(seqGrab);
	}
	
	seqGrab = NULL;
	iSightWindow = nil;

	
	if ([delegate respondsToSelector:@selector(iSightWillClose)]) {
		[delegate iSightWillClose];
	}
	
#if DEBUG
	[[graphView window] close];
#endif DEBUG
	
}


//Timer that updates the iSight view
- (void)idleTimer;
{
	
	OSErr err;
	if ((err = SGIdle(seqGrab)) != noErr)
		DLog(@"Error: SGIdle %d", err);

	// Look for a barcode in the frame
	// During debug one must press enter or click on the iSight window for the scan to happen
#if DEBUG
	if (scanBarcode) {
		scanBarcode = NO;
		[self processPixelBuffer];
	}
#else
	[self processPixelBuffer];
#endif DEBUG
}	


// Send a message to the delegate that we found a barcode
// Close the window if stayOpen is negative 
- (void)foundBarcode:(NSString *)aBarcode {

	if (stayOpen == NO)
		[iSightWindow close];

	
	// Only send barcode that we didn't previously scan
	// lastBarcode is reset to nil when calling scanBarcode
	if (lastBarcode == nil || ![lastBarcode isEqualToString:aBarcode]) {
		[[NSSound soundNamed:@"Morse"] play];	
    BOOL result = [delegate gotBarcode:aBarcode];
		if (result) {
      NSLog(@">> gotBarcode: succeed");
      [[NSSound soundNamed:@"Hero"] play];	
    }
    else {
      NSLog(@">> gotBarcode: failure");
      [[NSSound soundNamed:@"Basso"] play];	
    }
		[lastBarcode release];
		lastBarcode = [aBarcode retain];
	}
	
	//Clear barcode number arrays
	[self clear:self];
}

#pragma mark -
#pragma mark Barcode Scanning

- (void)processPixelBuffer {
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	/*	This is where it's being asked to process the pixel buffer for a barcode. Any other algorithms for 
		searching for the barcode should be inserted around here.  */
	
	int i, j; 
	int bottomMask, topMask;
	Ptr firstRowToScan = pixelBufferBaseAddress + ( bytesPerRow * FIRST_LINE_SCAN );
	int greenScalePixels[640];  //The value of the green pixel 0 - 255
	int greenDerivative[640];
	int xAxisCenterPoint = 320 - (NUMBER_OF_LINES_SCANNED / 2 * SPACING_BETWEEN_CENTERS); //initalize x center point
	foundBarcodeArea = NO;  //determine if to draw lines red or green
	BOOL noMissingNumbers = NO;  //check local number as all digits where deciphered
	
	//clear local number
	for (i = 0; i < 12; i = i++) {
		previousNumberLocalArray[0][i] = NOT_FOUND;
		previousNumberLocalArray[2][i] = 0;
	}

	//Do a number of rows from the same image centered in the middle with varying x axis center points
	for (i = 0; i < NUMBER_OF_LINES_SCANNED; i++) {
	
		//get green pixels for row
		[self getGreenFromRGB:firstRowToScan + (bytesPerRow * i * SPACING_BETWEEN_SCAN_LINE) to:greenScalePixels];
		
				
		//first derivative
		for (j = 0; j < 640; j++) {
			greenDerivative[j] = greenScalePixels[j + 1] - greenScalePixels[j];
		}
		
		//Find barcode area and information about max and min values of the pixels
		int startBarcode = 0, endBarcode = 639, minValue = 255, maxValue = 0;
		[self findStart:&startBarcode end:&endBarcode forLine:greenScalePixels derivative:greenDerivative centerAt:xAxisCenterPoint min:&minValue max:&maxValue];
		
		//move x center forward for the next row
		xAxisCenterPoint = xAxisCenterPoint + SPACING_BETWEEN_CENTERS;
		
		// A real barcode will not reach to the edge of the frame
		// if the end goes to the edge of the frame do not process
		if (endBarcode != 639) {
			
			
			
#ifdef DEBUG
			//Draw a green line of the green pixel values
			NSBezierPath *aPath = [NSBezierPath bezierPath];
			[aPath moveToPoint:NSMakePoint(0, greenScalePixels[0])];
			for (j = 1; j < 640; j++)
				[aPath lineToPoint:NSMakePoint(j, greenScalePixels[j])];
			[graphView setGreenPath:aPath];
			
			//Draw a blue line for the area of the barcode
			
			NSBezierPath *barcodeAreaPath = [NSBezierPath bezierPath];
			[barcodeAreaPath moveToPoint:NSMakePoint(startBarcode, greenScalePixels[startBarcode])];
			for (j = startBarcode; j < endBarcode; j++)
				[barcodeAreaPath lineToPoint:NSMakePoint(j, greenScalePixels[j])];
			[graphView setBluePath:barcodeAreaPath];
#endif DEBUG
						
			/*	This is a route is in development.
				Locating only the peaks of the barcode and infering the barcode from the peaks.
				Although the peaks contain less information they are not affected by edge blurring
				So using the space between peaks and statistical analysis could lead to the barcode
				Normalized distance between peaks should reflect the following:
					1 would mean it's 1 black stripe and 1 white stripe
					1.5 would mean it's 1 black and 2 white or 2 black and 1 white;
					2  =  1-3, 2-2, 3-1
					2.5  = 1-4, 2-3, 3-2, 1-4
				Using the next sorounding distances it can tell which possability it should be.
				Maybe even using the distance between peak and valley might be better
			*/
			//[self getPeakDistance:barsArray forLine:greenScalePixels start:startBarcode end:endBarcode];
			
			
			
			int differenceInRange =  maxValue - minValue;
						
			// repeat for different values of the masks
			// the masks were determined throw test cases
			for (j =0; j < 5; j++) {
				
				// this array holds the thickness of each stripe, starting with 0101
				// meaning the first four are all 1 in thickness, so the array would hold 1,1,1,1
				int barsArray[62] = {0};
				
				if (j == 0) {
					bottomMask = minValue + (differenceInRange * 0.34);
					topMask = maxValue - (differenceInRange * 0.44);
				}
				else if (j == 1) {
					bottomMask = minValue + (differenceInRange * 0.15);
					topMask = maxValue - (differenceInRange * 0.4);
				}
				else if (j == 2) {
					bottomMask = minValue + (differenceInRange * 0.3);
					topMask = maxValue - (differenceInRange * 0.3);
				}
				else if (j == 3) {
					bottomMask = minValue + (differenceInRange * 0.18);
					topMask = maxValue - (differenceInRange * 0.5);
				}
				
				/*  //These masks are not very useful 
				else if (j == 4) {
					bottomMask = minValue + (differenceInRange * 0.39);
					topMask = maxValue - (differenceInRange * 0.25);
				}
				else if (j == 5) {
					bottomMask = minValue + (differenceInRange * 0.32);
					topMask = maxValue - (differenceInRange * 0.17);
				}
				 */
				
				else  {
					bottomMask = minValue + (differenceInRange * 0.1);
					topMask = maxValue - (differenceInRange * 0.25);
				}
				
				//Get the bar width information based on the mask
				[self getBars:barsArray forLine:greenScalePixels derivative:greenDerivative start:startBarcode end:endBarcode top:topMask bottom:bottomMask];
				
				//NSLog(@"bars %@", [self stringFromBars:barsArray]);
				
				//Try to read a number based on the bars widths
				numberOfDigitsFound = 0;
				[self readBars:barsArray];
				
				//NSLog(@"Scanned %@  local:%@  j:%d", [self stringFromArrray:numberArray], [self stringFromArrray:previousNumberLocalArray], j);
				
				// If 7 or more digits were read from the barcode then process number 
				// and add it to the local number 
				// Don't check the scanned number if it has 12 digits as it not verfied and it could lead to a lucky checksum and a wrong number
				if (numberOfDigitsFound >= MINIMUM_DIGITS_FOR_GOOD_SCAN) {
					//NSLog(@"j = %d %d", j, numberOfDigitsFound);
					foundBarcodeArea = YES;	 //Tells the sequence grabber to draw the lines green as feedback to the user	
					noMissingNumbers = [self compareAgainstPreviousScans:numberArray previous:previousNumberLocalArray];
				}
			}
		}
	}
	
	/*	The compareAgainstPreviousScans: not only compares the numbers but builds how sure it is about the number based on previous
		comparisons. There are two numbers that are built this way. The local number based on all scan lines and the different masks for each line.
		And a global number based on all the local numbers for each frame.
	 */
	
	//check the local number if it has no missing numbers run the checksum
	if (noMissingNumbers) {
		if ([self checkCheckDigit:previousNumberLocalArray]) {
			NSString *barcodeString = [self barcodeFromArray:previousNumberLocalArray];

				//NSLog(@"Found local %@", barcodeString);
				[self foundBarcode:barcodeString];
				[pool release];
				return; //Otherwise it might sent another message with the global matches as well
		}
	}

	
	//NSLog(@"local %@", [self stringFromArrray:previousNumberLocalArray]);
	
	//Add the local number to the global number and
	//check the global number if it has no missing numbers run the checksum
	if ([self compareAgainstPreviousScans:previousNumberLocalArray previous:previousNumberGlobalArray] == YES) {
		if ([self checkCheckDigit:previousNumberGlobalArray]) {
			NSString *barcodeString = [self barcodeFromArray:previousNumberGlobalArray];
			//NSLog(@"Found global %@", barcodeString);
			[self foundBarcode:barcodeString];
		}
	}
	
	[pool release];
	
	//NSLog(@"Global %@", [self stringFromArrray:previousNumberGlobalArray]);
}




// Determine the area of the barcode by using the supplied center and determining the average change of direction
// As soon as something is below 1/4 of the variation in height for more than the average spacing time MULTIPLY_AVERAGE_SPACING, then the barcode ends
- (void)findStart:(int *)startBarcode end:(int *)endBarcode forLine:(int *)pixelLineArray derivative:(int *)lineDerivativeArray centerAt:(int)centerX min:(int *)minValue max:(int *)maxValue {
	
	int averageSpacing = 0, numberOfCurves = 0, spacingInThisRun = 0;
	int i, count, startScan = centerX - 40, endScan = centerX + 40;
	
	BOOL positive = YES;
	if (lineDerivativeArray[startScan] < 0)
		positive = NO;
	
	
	//Build the average spacing number and the variation in height from a smaple around the center
	for (i = startScan; i < endScan; i++) {
		
		if (*maxValue < pixelLineArray[i])
			*maxValue = pixelLineArray[i];
		else if (*minValue > pixelLineArray[i])
			*minValue = pixelLineArray[i];
		
		
		if (lineDerivativeArray[i] < 0) {
			if (positive) {
				positive = NO;
				averageSpacing = averageSpacing + spacingInThisRun;
				numberOfCurves++;
				spacingInThisRun = 0;
			}
			
		}
		else {
			if (!positive) {
				positive = YES;
				averageSpacing = averageSpacing + spacingInThisRun;
				numberOfCurves++;
				spacingInThisRun = 0;
			}
		}
		
		spacingInThisRun++;
	}
	
	//If there was a solid growing gradient with no curves then return
	if (numberOfCurves == 0)
		return;
	
	
	averageSpacing = (averageSpacing / numberOfCurves) * MULTIPLY_AVERAGE_SPACING;
	
	//NSLog(@"min %d max %d spacing: %d", *minValue, *maxValue, averageSpacing);
	int quarterHeight = ((*maxValue - *minValue) * 0.25);
	int bottomForth = *minValue + quarterHeight;
	int topForth = *maxValue - quarterHeight;
	
	//anything below oneForth for averageSpacing * MULTIPLY_AVERAGE_SPACING is the end of the barcode
	for (i = centerX, count = 0; i > 0; i--) {
		if (pixelLineArray[i] < bottomForth || pixelLineArray[i] > topForth) {
			count++;
		}
		else {
			count = 0;
			*startBarcode = i;
		}
		
		if (count > averageSpacing) {
			break;
		}
	}
	
	for (i = centerX, count = 0; i < 640; i++) {
		if (pixelLineArray[i] < bottomForth || pixelLineArray[i] > topForth) {
			count++;
		}
		else {
			count = 0;
			*endBarcode = i;
		}
		
		if (count > averageSpacing) {
			break;
		}
	}
	
	//NSLog(@"beginning: %d end %d", *startBarcode, *endBarcode);
}




//given an array of pixel values and the first derivative as well as the area of the barcode it goes throw determining the bar lengths.
- (void)getBars:(int [62])barsArrayOneDimension forLine:(int *)pixelLineArray derivative:(int *)lineDerivativeArray start:(int)startBarcode end:(int)endBarcode top:(int)topMask bottom:(int)bottomMask {
	
	
	int i, sectionThickness = 0;
	BOOL blackSection = YES;
	int nextSection = 0;
	BOOL binaryValueOfPixel;
	float barWidth = (endBarcode - startBarcode) / 96.0;  //What a single bar width should be
	
	//For the entire area of the barcode
	for (i = startBarcode; i < endBarcode, nextSection < 62; i++) {
		
		
		// Determine the binaryValue of the pixel
		binaryValueOfPixel = [self getBinaryValueForPixel:pixelLineArray[i] derivativeForPixel:lineDerivativeArray[i] top:topMask bottom:bottomMask];

		//black pixel
		if (binaryValueOfPixel == NO) {
			
			// We are not in a black section, determine the previous white bar width
			if (!blackSection) {
				
				//Get bar width
				int stripes = getNumberStripesEAN(sectionThickness, barWidth);
				
				barsArrayOneDimension[nextSection] = stripes;
				nextSection++;
				
				sectionThickness = 0;
			}
			
			//set black section
			blackSection = YES;
			sectionThickness++;
		}
		//White pixel
		else {
			
			//We are not in a white section, determine the previous black bar width
			if (blackSection) {
				
				//Get bar width
				int stripes = getNumberStripesEAN(sectionThickness, barWidth);

				
				barsArrayOneDimension[nextSection] = stripes;
				nextSection++;
				
				sectionThickness = 0;
			}
			
			//set white section
			blackSection = NO;
			sectionThickness++;
			
		}
	}
}


// Determines if a pixel is black or white depending on the mask provided and if not on the first derivative
// A possability is changing the first derivative to the second derivative to be more precise about the midpoint
// or even a simple midpoint calculation between the peak and the valley
- (BOOL)getBinaryValueForPixel:(int)pixelValue derivativeForPixel:(int)derivative top:(int)topMask bottom:(int)bottomMask {
	
	if (pixelValue > topMask) {
		return YES;
	}
	else if (pixelValue < bottomMask) {
		return NO;
	}
	else {
		
		//use derivative
		if (derivative < 0) {
			return YES;
		}
		else {
			return NO;
		}
	}	
}

//given a array of bar thickness it read four bars at a time and determines the number based on the encoding 
- (void)readBars:(int [62])lastBinaryData {
	
	int i, k;
	
	//Starts with 0101
	if (lastBinaryData[0] == 1 && lastBinaryData[1] == 1 && lastBinaryData[2] == 1 && lastBinaryData[3] == 1)  {
		
		
		//First number has to be odd encoded			
		[self getNumberForLocation:&lastBinaryData[4]  encoding:MKLeftHandEncodingOdd location:0];
		if (numberArray[0][0] != NOT_FOUND)
			numberOfDigitsFound++;
		
		
		//First Section left hand encoding even or odd
		for (i = 8, k = 1; i < 28; i = i + 4, k++) {
			
			[self getNumberForLocation:&lastBinaryData[i] encoding:MKLeftHandEncodingBoth location:k];
			
			if (numberArray[0][k] != NOT_FOUND)
				numberOfDigitsFound++;
			
		}
		
		//Second section all right hand encoding
		for (i = 33, k = 6; i < 57; i = i + 4, k++) {
			
			[self getNumberForLocation:&lastBinaryData[i] encoding:MKRightHandEncoding location:k];
			
			if (numberArray[0][k] != NOT_FOUND)
				numberOfDigitsFound++;
		}
	}
	else {
		//Clear number as it's not scanning
		for (i = 0; i < 12; i = i++) {
			numberArray[0][i] = NOT_FOUND;
			//numberArray[3][i] = 0;
		}
	}
	
}


// Given an array of bar lengths an index to begin the scan,  it scans the next four bars and determines the number
// based on the UPC/EAN encoding
// For more info check out: http://www.barcodeisland.com/ean13.phtml
- (void)getNumberForLocation:(int *)anArray encoding:(int)encodingType location:(int)numberIndex {
	
	//All 6 numbers on the right hand of the code have a single encoding
	if (encodingType == MKRightHandEncoding) {
		numberArray[1][numberIndex] = 0;
		
		if (anArray[0] == 3 && anArray[1]  == 2 && anArray[2] == 1 && anArray[3] == 1) 
		{
			numberArray[0][numberIndex] = 0;
			return;
		}
		else if (anArray[0] == 2 && anArray[1]  == 2 && anArray[2] == 2 && anArray[3] == 1) 
		{
			numberArray[0][numberIndex] = 1;
			return;
		}
		else if (anArray[0] == 2 && anArray[1]  == 1 && anArray[2] == 2 && anArray[3] == 2) 
		{
			numberArray[0][numberIndex] = 2;
			return;
		}
		else if (anArray[0] == 1 && anArray[1]  == 4 && anArray[2] == 1 && anArray[3] == 1)
		{
			numberArray[0][numberIndex] = 3;
			return;
		}
		else if (anArray[0] == 1 && anArray[1]  == 1 && anArray[2] == 3 && anArray[3] == 2) 
		{
			numberArray[0][numberIndex] = 4;
			return;
		}
		else if (anArray[0] == 1 && anArray[1]  == 2 && anArray[2] == 3 && anArray[3] == 1) 
		{
			numberArray[0][numberIndex] = 5;
			return;
		}
		else if (anArray[0] == 1 && anArray[1]  == 1 && anArray[2] == 1 && anArray[3] == 4) 
		{
			numberArray[0][numberIndex] = 6;
			return;
		}
		else if (anArray[0] == 1 && anArray[1]  == 3 && anArray[2] == 1 && anArray[3] == 2) 
		{
			numberArray[0][numberIndex] = 7;
			return;
		}
		else if (anArray[0] == 1 && anArray[1]  == 2 && anArray[2] == 1 && anArray[3] == 3) 
		{
			numberArray[0][numberIndex] = 8;
			return;
		}
		else if (anArray[0] == 3 && anArray[1]  == 1 && anArray[2] == 1 && anArray[3] == 2) 
		{
			numberArray[0][numberIndex] = 9;
			return;
		}
		
		numberArray[0][numberIndex] = NOT_FOUND;
		return;
		
	}
	
	//the first 6 numbers on the left hand has two encodings that allow it to determine the 13 number for EAN numbers
	
	//odd parity
	if (anArray[0] == 3 && anArray[1]  == 2 && anArray[2] == 1 && anArray[3] == 1) //isEqualToString:@"0001101"])
	{
		numberArray[0][numberIndex] = 0;
		numberArray[1][numberIndex] = 1;
		return;
	}
	else if (anArray[0] == 2 && anArray[1]  == 2 && anArray[2] == 2 && anArray[3] == 1) //isEqualToString:@"0011001"])
	{
		numberArray[0][numberIndex] = 1;
		numberArray[1][numberIndex] = 1;
		return;
	}
	else if (anArray[0] == 2 && anArray[1]  == 1 && anArray[2] == 2 && anArray[3] == 2) //isEqualToString:@"0010011"])
	{
		numberArray[0][numberIndex] = 2;
		numberArray[1][numberIndex] = 1;
		return;
	}
	else if (anArray[0] == 1 && anArray[1]  == 4 && anArray[2] == 1 && anArray[3] == 1) //isEqualToString:@"0111101"])
	{
		numberArray[0][numberIndex] = 3;
		numberArray[1][numberIndex] = 1;
		return;
	}
	else if (anArray[0] == 1 && anArray[1]  == 1 && anArray[2] == 3 && anArray[3] == 2) //isEqualToString:@"0100011"])
	{
		numberArray[0][numberIndex] = 4;
		numberArray[1][numberIndex] = 1;
		return;
	}
	else if (anArray[0] == 1 && anArray[1]  == 2 && anArray[2] == 3 && anArray[3] == 1) //isEqualToString:@"0110001"])
	{
		numberArray[0][numberIndex] = 5;
		numberArray[1][numberIndex] = 1;
		return;
	}
	else if (anArray[0] == 1 && anArray[1]  == 1 && anArray[2] == 1 && anArray[3] == 4) //isEqualToString:@"0101111"])
	{
		numberArray[0][numberIndex] = 6;
		numberArray[1][numberIndex] = 1;
		return;
	}
	else if (anArray[0] == 1 && anArray[1]  == 3 && anArray[2] == 1 && anArray[3] == 2) //isEqualToString:@"0111011"])
	{
		numberArray[0][numberIndex] = 7;
		numberArray[1][numberIndex] = 1;
		return;
	}
	else if (anArray[0] == 1 && anArray[1]  == 2 && anArray[2] == 1 && anArray[3] == 3) //isEqualToString:@"0110111"])
	{
		numberArray[0][numberIndex] = 8;
		numberArray[1][numberIndex] = 1;
		return;
	}
	else if (anArray[0] == 3 && anArray[1]  == 1 && anArray[2] == 1 && anArray[3] == 2) //isEqualToString:@"0001011"])
	{
		numberArray[0][numberIndex] = 9;
		numberArray[1][numberIndex] = 1;
		return;
	}
		
	
	//even parity
	if (encodingType == MKLeftHandEncodingBoth) {
		if (anArray[0] == 1 && anArray[1]  == 1 && anArray[2] == 2 && anArray[3] == 3) 
		{
			numberArray[0][numberIndex] = 0;
			numberArray[1][numberIndex] = 0;
			return;
		}
		else if (anArray[0] == 1 && anArray[1]  == 2 && anArray[2] == 2 && anArray[3] == 2) 
		{
			numberArray[0][numberIndex] = 1;
			numberArray[1][numberIndex] = 0;
			return;
		}
		else if (anArray[0] == 2 && anArray[1]  == 2 && anArray[2] == 2 && anArray[3] == 2) 
		{
			numberArray[0][numberIndex] = 2;
			numberArray[1][numberIndex] = 0;
			return;
		}
		else if (anArray[0] == 1 && anArray[1]  == 1 && anArray[2] == 4 && anArray[3] == 1)
		{
			numberArray[0][numberIndex] = 3;
			numberArray[1][numberIndex] = 0;
			return;
		}
		else if (anArray[0] == 2 && anArray[1]  == 3 && anArray[2] == 1 && anArray[3] == 1) 
		{
			numberArray[0][numberIndex] = 4;
			numberArray[1][numberIndex] = 0;
			return;
		}
		else if (anArray[0] == 1 && anArray[1]  == 3 && anArray[2] == 2 && anArray[3] == 1) 
		{
			numberArray[0][numberIndex] = 5;
			numberArray[1][numberIndex] = 0;
			return;
		}
		else if (anArray[0] == 4 && anArray[1]  == 1 && anArray[2] == 1 && anArray[3] == 1) 
		{
			numberArray[0][numberIndex] = 6;
			numberArray[1][numberIndex] = 0;
			return;
		}
		else if (anArray[0] == 2 && anArray[1]  == 1 && anArray[2] == 3 && anArray[3] == 1) 
		{
			numberArray[0][numberIndex] = 7;
			numberArray[1][numberIndex] = 0;
			return;
		}
		else if (anArray[0] == 3 && anArray[1]  == 1 && anArray[2] == 2 && anArray[3] == 1) 
		{
			numberArray[0][numberIndex] = 8;
			numberArray[1][numberIndex] = 0;
			return;
		}
		else if (anArray[0] == 2 && anArray[1]  == 1 && anArray[2] == 1 && anArray[3] == 3) 
		{
			numberArray[0][numberIndex] = 9;
			numberArray[1][numberIndex] = 0;
			return;
		}
	}
	
	
	// Code could be added here if a number is not found, then check the neighbours and see if they include a large white or black bar that might
	// throw the bar thickness of for this section and correct for that error 
	
	numberArray[0][numberIndex] = NOT_FOUND;
}


//Get the Green pixel value for a row from the Pixel buffer
- (void)getGreenFromRGB:(char *)rowPointer to:(int *)anArray640 {
	int i;
	
	//if mirrored start at the back of the frame and scan forward
	if (mirrored == NO) {
		for (i = 0; i < 640; i++) {
			anArray640[i] = (UInt8)*(rowPointer + (i * SAMPLES_PER_PIXEL) +2) ;
			anArray640[i] = 255 - anArray640[i];
		}
	}
	else {
		for (i = 639; i >= 0; i--) {
			anArray640[639-i] = (UInt8)*(rowPointer + (i * SAMPLES_PER_PIXEL) +2) ;
			anArray640[639-i] = 255 - anArray640[639-i];
		}
	}
	

}


//Given a number of consecutive equal binary values and the average thickness of single bar it returns the thickness of the bar
int getNumberStripesEAN(int number, double average) {
	double ratioToAverageThickness = number / average;
	if (ratioToAverageThickness < 1.5)
		return 1;
	else if (ratioToAverageThickness < 2.5)
		return 2;
	else if (ratioToAverageThickness < SEPARATION_VALUE_FOR_3_BARS)
		return 3;
	else 
		return 4;

}



- (void)clear:(id)sender {
	int i;
	for (i = 0; i < 12; i = i++) {
		previousNumberGlobalArray[0][i] = NOT_FOUND;
		previousNumberGlobalArray[2][i] = 0;
	}
	
	
	//NSLog(@"Clear: %@", [self stringFromArrray:previousNumberLocalArray]);
}



- (BOOL)checkCheckDigit:(char [3][12])aNumberArray {
	
	//first build the first number from odd even parity and store it index 6 of the odd even array [1][6]
	if (aNumberArray[1][1] == 1) { 
		if (aNumberArray[1][2] == 1)  {  // odd odd
			aNumberArray[1][6] = 0;			//12 digit UPC first number is 0
			if (aNumberArray[1][3] != 1 || aNumberArray[1][4] != 1 || aNumberArray[1][5] != 1) //check the rest
				return NO;
		}
		else {
			if (aNumberArray[1][3] == 1)  {  
				aNumberArray[1][6] = 1;	// odd even odd
				if (aNumberArray[1][4] != 0 || aNumberArray[1][5] != 0) //check the rest
					return NO;
			}
			else {
				if (aNumberArray[1][4] == 1)  {  
					aNumberArray[1][6] = 2;	// odd even even odd
					if (aNumberArray[1][5] != 0) //check the rest
						return NO;
				}
				else {
					aNumberArray[1][6] = 3;	 // odd even even even
					if (aNumberArray[1][5] != 1) //check the rest
						return NO;
				}
			}
		}
	}
	else {
		
		if (aNumberArray[1][2] == 1)  {  // even odd
			if (aNumberArray[1][3] == 1)  {  
				aNumberArray[1][6] = 4;	// even odd odd 
				if (aNumberArray[1][4] != 0 || aNumberArray[1][5] != 0) //check the rest
					return NO;
			}
			else {
				if (aNumberArray[1][4] == 1)  {  
					aNumberArray[1][6] = 7;	// even odd even odd
					if (aNumberArray[1][5] != 0) //check the rest
						return NO;
				}
				else {
					aNumberArray[1][6] = 8;	 // even odd even even
					if (aNumberArray[1][5] != 1) //check the rest
						return NO;
				}
			}
		}
		else {
			if (aNumberArray[1][3] == 1)  {  
				if (aNumberArray[1][4] == 1)  {  
					aNumberArray[1][6] = 5;	// even even odd odd
					if (aNumberArray[1][5] != 0) //check the rest
						return NO;
				}
				else {
					aNumberArray[1][6] = 9;	// even even odd even
					if (aNumberArray[1][5] != 1) //check the rest
						return NO;
					
				}
			}
			else {
				aNumberArray[1][6] = 6;	// even even even
				if (aNumberArray[1][4] != 1 || aNumberArray[1][5] != 1) //check the rest
					return NO;
			}
		}
	}
	
	//NSLog(@"numberToCheck %@", [NSString stringWithFormat:@"%d%@", aNumberArray[1][6], [self stringFromArrray:aNumberArray]]);
	
	
	//check digit
	// the first digit is in [1][6] starting with second digit really
	// 11 becasue we want to leave the check digit out of the calculation
	int i, checkDigitSum = aNumberArray[1][6];
	for (i = 0; i < 11; i++) {
		if ( i % 2)
			checkDigitSum = checkDigitSum + aNumberArray[0][i];
		else
			checkDigitSum = checkDigitSum + (aNumberArray[0][i] * 3);
		
	}
	
	//NSLog(@"check Sum %d", checkDigitSum);
	
	checkDigitSum = 10 - (checkDigitSum % 10);
	
	//NSLog(@"check %d == %d", checkDigitSum, aNumberArray[0][11]);
	
	if (checkDigitSum == aNumberArray[0][11] || (checkDigitSum == 10 && aNumberArray[0][11] == 0))
		return YES;
	
	return NO;
}


// Compares two barcode numbers and merges them intelligently. That way not wasting previous scans. It keeps a table of how sure it is about a number depending on how many times that number has appeared at that location
- (BOOL)compareAgainstPreviousScans:(char [3][12])aNumberArray previous:(char [3][12])previousNumberArray {
	
	int i;
	BOOL completeNumber = YES;
	
	for (i = 0; i < 12; i++) {
		//check other results to fill in ?
		if (previousNumberArray[0][i] != NOT_FOUND ) {			
			//Number are equal increase sureness until limit
			if (previousNumberArray[0][i] == aNumberArray[0][i]) {
				if (previousNumberArray[2][i] != SURENESS_LIMIT)
					++previousNumberArray[2][i];
			}
			else {
				
				if (aNumberArray[0][i] == NOT_FOUND) {
					// A aNumberArray is never used so no need to fill it
					//aNumberArray[0][i] = previousNumberArray[0][i];
					//aNumberArray[1][i] = previousNumberArray[1][i];
				}
				else {
					// decide on the sureness index which one stays
					// if the previous number sureness ahs dipped under 0 then replace it with the current number 
					// else if the current number sureness is higher than previous number then replace previous number as well
					// subtract 1 from sureness as the numbers where not matching
					if (previousNumberArray[2][i] < 0) {
						previousNumberArray[0][i] = aNumberArray[0][i];
						previousNumberArray[1][i] = aNumberArray[1][i];	
						previousNumberArray[2][i] = 0;
					}
					else {
						if (previousNumberArray[2][i] < aNumberArray[0][i]) {
							previousNumberArray[0][i] = aNumberArray[0][i];
							//previousNumberArray[1][i] = aNumberArray[1][i];	// We leave this line out as we don't want to carry the surenees from a single bad scan
						}
						--previousNumberArray[2][i];
					}
				}
			}
		}
		else {
			if (aNumberArray[0][i] == NOT_FOUND ) {
				completeNumber = NO;
			}
			else {
				previousNumberArray[0][i] = aNumberArray[0][i];	
				previousNumberArray[1][i] = aNumberArray[1][i];	
				previousNumberArray[2][i] = 0;
			}
		}
		
	}
	
	return completeNumber;
}







#pragma mark -
#pragma mark sharedInstance

static MyBarcodeScanner *sharedInstance = nil;

+ (MyBarcodeScanner *)sharedInstance {	
	if (sharedInstance == nil) {
		sharedInstance = [[self alloc] init];
	}
	return sharedInstance;
}
- (void)release {
}
- (id)retain {
    return self;
}
- (unsigned)retainCount {
    return UINT_MAX;
}
+ (id)allocWithZone:(NSZone *)zone {
	if (sharedInstance == nil) {
		return [super allocWithZone:zone];
	}
    return sharedInstance;
}
- (id)copyWithZone:(NSZone *)zone {
    return self;
}
- (id)autorelease {
    return self;
}

#pragma mark Accessors

- (void)setDelegate:(id)aDelegate {
	[delegate release];
	delegate = [aDelegate retain];
}

- (void)setStaysOpen:(BOOL)stayOpenValue {
	stayOpen = stayOpenValue;
}

- (void)setMirrored:(BOOL)mirroredValue {
	mirrored = mirroredValue;
}

- (id)iSightWindow {
  return iSightWindow;
}
#pragma mark -
#pragma mark Sequence Grabber code

/* ---------------------------------------------------------------------- */
/* sequence grabber data procedure - this is where the work is done

 MungGrabDataProc - the sequence grabber calls the data function whenever
   any of the grabber’s channels write digitized data to the destination movie file.
   
   NOTE: We really mean any, if you have an audio and video channel then the DataProc will
   		 be called for either channel whenever data has been captured. Be sure to check which
   		 channel is being passed in. In this example we never create an audio channel so we know
   		 we're always dealing with video.
   
   This data function does two things, it first decompresses captured video
   data into an offscreen GWorld, draws some status information onto the frame then
   transfers the frame to an onscreen window.
   
   For more information refer to Inside Macintosh: QuickTime Components, page 5-120
   c - the channel component that is writing the digitized data.
   p - a pointer to the digitized data.
   len - the number of bytes of digitized data.
   offset - a pointer to a field that may specify where you are to write the digitized data,
   			and that is to receive a value indicating where you wrote the data.
   chRefCon - per channel reference constant specified using SGSetChannelRefCon.
   time	- the starting time of the data, in the channel’s time scale.
   writeType - the type of write operation being performed.
   		seqGrabWriteAppend - Append new data.
   		seqGrabWriteReserve - Do not write data. Instead, reserve space for the amount of data
   							  specified in the len parameter.
   		seqGrabWriteFill - Write data into the location specified by offset. Used to fill the space
   						   previously reserved with seqGrabWriteReserve. The Sequence Grabber may
   						   call the DataProc several times to fill a single reserved location.
   refCon - the reference constant you specified when you assigned your data function to the sequence grabber.
*/
pascal OSErr MungGrabDataProc(SGChannel c, Ptr p, long len, long *offset, long chRefCon, TimeValue time, short writeType, long refCon)
{
#pragma unused(offset,chRefCon,writeType,refCon)

    CGrafPtr	theSavedPort;
    GDHandle    theSavedDevice;
    CodecFlags	ignore;
    //float		fps = 0,
	// 			averagefps = 0;
    //char		status[64];
	//Str255		theString; 
    
    ComponentResult err = noErr;
	
	// reset frame and time counters after a stop/start
	if (gMungData->lastTime > time) {
		gMungData->lastTime = 0;
		gMungData->frameCount = 0;
	}
    
    gMungData->frameCount++;
        
    if (gMungData->timeScale == 0) {
    	// first time here so set the time scale
    	err = SGGetChannelTimeScale(c, &gMungData->timeScale);
		if (err)  {	return err;}
    }
    
	if (gMungData->pGWorld) {
    	if (gMungData->decomSeq == 0) {
    		// Set up getting grabbed data into the GWorld
    		
    		Rect				   sourceRect = { 0, 0 };
			MatrixRecord		   scaleMatrix;
			ImageDescriptionHandle imageDesc = (ImageDescriptionHandle)NewHandle(0);
            
            // retrieve a channel’s current sample description, the channel returns a sample description that is
            // appropriate to the type of data being captured
            err = SGGetChannelSampleDescription(c, (Handle)imageDesc);
			if (err)  {	return err;}
            
                  
            // make a scaling matrix for the sequence
			sourceRect.right = (**imageDesc).width;
			sourceRect.bottom = (**imageDesc).height;
			RectMatrix(&scaleMatrix, &sourceRect, &gMungData->boundsRect);
			
			//mirror image flip on the y-axis  (frame rate is slower)
			if (mirrored) {
				ScaleMatrix(&scaleMatrix, Long2Fix(-1), fixed1, 0, 0);
				TranslateMatrix(&scaleMatrix, Long2Fix(sourceRect.right), 0);
			} 
			
#ifdef DEBUG
	DLog(@"%f %f %f\n%f %f %f\n%f %f %f\n", scaleMatrix.matrix[0][0], scaleMatrix.matrix[0][1], scaleMatrix.matrix[0][2], scaleMatrix.matrix[1][0], scaleMatrix.matrix[1][1], scaleMatrix.matrix[1][2],scaleMatrix.matrix[2][0], scaleMatrix.matrix[2][1], scaleMatrix.matrix[2][2]);
#endif DEBUG
			
            // begin the process of decompressing a sequence of frames
            // this is a set-up call and is only called once for the sequence - the ICM will interrogate different codecs
            // and construct a suitable decompression chain, as this is a time consuming process we don't want to do this
            // once per frame (eg. by using DecompressImage)
            // for more information see Ice Floe #8 http://developer.apple.com/quicktime/icefloe/dispatch008.html
            // the destination is specified as the GWorld
			err = DecompressSequenceBegin(&gMungData->decomSeq,	// pointer to field to receive unique ID for sequence
										  imageDesc,			// handle to image description structure
										  gMungData->pGWorld,   // port for the DESTINATION image
										  NULL,					// graphics device handle, if port is set, set to NULL
										  NULL,					// source rectangle defining the portion of the image to decompress 
                                          &scaleMatrix,			// transformation matrix
                                          srcCopy,				// transfer mode specifier
                                          (RgnHandle)NULL,		// clipping region in dest. coordinate system to use as a mask
                                          nil,					// flags
                                          codecLosslessQuality, 	// accuracy in decompression
                                          bestFidelityCodec);		// compressor identifier or special identifiers ie. bestSpeedCodec
			if (err)  {	return err;}
            
            DisposeHandle((Handle)imageDesc);         
            
            // Set up getting grabbed data into the Window
            
            // create the image sequence for the offscreen
            err = MakeImageSequenceForGWorld(gMungData->pGWorld,
            								 GetWindowPort(gMungData->pWindow),
            								 &gMungData->drawSize,
            								 &gMungData->drawSeq);
			if (err)  {	return err;}
        }
        
        // decompress a frame into the GWorld - can queue a frame for async decompression when passed in a completion proc
        err = DecompressSequenceFrameS(gMungData->decomSeq,	// sequence ID returned by DecompressSequenceBegin
        							   p,					// pointer to compressed image data
        							   len,					// size of the buffer
        							   0,					// in flags
        							   &ignore,				// out flags
        							   NULL);				// async completion proc

		if (err) {
			DLog(@"Error: Decompression of frame gave error: %d", err);
		} else {	
			// write status information onto the frame	  		
	       	GetGWorld(&theSavedPort, &theSavedDevice);
	       	SetGWorld(gMungData->pGWorld, NULL);
	       
	       //	TextSize(12);
	       //	TextMode(srcCopy);
	     //  	MoveTo(gMungData->boundsRect.left, gMungData->boundsRect.top + 120);
	       	//fps = (float)gMungData->timeScale / (float)(time - gMungData->lastTime);
	       	//averagefps = ((float)gMungData->frameCount * (float)gMungData->timeScale) / (float)time;
	       	//sprintf(status, "time stamp: %ld, fps:%5.1f average fps:%5.1f", time, fps, averagefps);
			//sprintf(status, "IIIIIIIIIIIIIIIIII");
	       	//CopyCStringToPascal(status, theString);
	       	//DrawString(theString);
			
			
			//Draw lines in green if the barcode was found that more than 6 digits could be identified otherwise red
			if (foundBarcodeArea)
				ForeColor(greenColor);
			else
				ForeColor(redColor);

			int i;
			for (i = 0; i < NUMBER_OF_LINES_SCANNED; i++) {
				i * SPACING_BETWEEN_SCAN_LINE;
				MoveTo(gMungData->boundsRect.left + 200, gMungData->boundsRect.top + FIRST_LINE_SCAN + (i * SPACING_BETWEEN_SCAN_LINE) +1);
				LineTo(gMungData->boundsRect.left + 440, gMungData->boundsRect.top + FIRST_LINE_SCAN + (i * SPACING_BETWEEN_SCAN_LINE) +1);

			}
			 
			
			
			// An attempt at doing the above line drawings using Quartz
			// As to avoid the deprecated QuickDraw functions
			/*
			CGContextRef myContext;
			
			SetPortWindowPort (theWindowDrawing);// 1
			QDBeginCGContext (GetWindowPort (theWindowDrawing), &myContext);
			
			int i, startLine = (240 - (NUMBER_OF_LINES_SCANNED /2 * SPACING_BETWEEN_SCAN_LINE));
			for (i = 0; i < NUMBER_OF_LINES_SCANNED; i++) {
				i * SPACING_BETWEEN_SCAN_LINE;
				CGContextMoveToPoint(myContext,gMungData->boundsRect.left + 80,gMungData->boundsRect.top + startLine + (i * SPACING_BETWEEN_SCAN_LINE) +1);
				CGContextAddLineToPoint(myContext,gMungData->boundsRect.left + 540,gMungData->boundsRect.top + startLine + (i * SPACING_BETWEEN_SCAN_LINE) +1);	
			}
			CGContextStrokePath(myContext);
			 QDEndCGContext (GetWindowPort(theWindowDrawing), &myContext);
			 */

			
			SetGWorld(theSavedPort, theSavedDevice);
	       
	       	// draw the frame to the destination, in this case the onscreen window      
			err = DecompressSequenceFrameS(gMungData->drawSeq,									// sequence ID
	       							   	   GetPixBaseAddr(GetGWorldPixMap(gMungData->pGWorld)),	// pointer image data
	       							   	   gMungData->drawSize,									// size of the buffer
	       							   	   0,													// in flags
	       							   	   &ignore,												// out flags
	       							   	   NULL); 												// can async help us?
			
			
			// look for a barcode in the frame
			// Was causing a crash as the window is release when a positive match is done
			// moved it to the idleTimer 
			//[(MyBarcodeScanner *)refCon processPixelBuffer];
			
		}
	}
	return 0;
}



// --------------------
// InitializeMungData
//
OSErr InitializeMungData(Rect inBounds, WindowRef inWindow)
{
    CGrafPtr theOldPort;
    GDHandle theOldDevice;
    
    OSErr err = noErr;
    
    // allocate memory for the data
    gMungData = (MungDataPtr)NewPtrClear(sizeof(MungDataRecord));
    if (MemError() || NULL == gMungData ) return nil;
    
    // create a GWorld
    err = QTNewGWorld(&(gMungData->pGWorld),	// returned GWorld
					  k32ARGBPixelFormat,		// pixel format
					  &inBounds,				// bounds
					  0,						// color table
					  NULL,					// GDHandle
					  0);						// flags
	if (err)  {	return err;}
    
    // lock the pixmap and make sure it's locked because
    // we can't decompress into an unlocked pixmap
    if(!LockPixels(GetGWorldPixMap(gMungData->pGWorld)))
		if (err)  {	return err;}
			
			GetGWorld(&theOldPort, &theOldDevice);    
    SetGWorld(gMungData->pGWorld, NULL);
    BackColor(blackColor);
    ForeColor(whiteColor);
    EraseRect(&inBounds);    
    SetGWorld(theOldPort, theOldDevice);
	
	gMungData->boundsRect = inBounds;
	gMungData->pWindow = inWindow;
	
	return 0;
}

// --------------------
// MakeImageSequenceForGWorld
//
OSErr MakeImageSequenceForGWorld(GWorldPtr pGWorld, GWorldPtr pDest, long *imageSize, ImageSequence *seq)
{
    ImageDescriptionHandle desc = NULL;
    PixMapHandle hPixMap = GetGWorldPixMap(pGWorld);
    Rect bounds;
    
    OSErr err = noErr;
    
    GetPixBounds(hPixMap, &bounds);
	
    *seq = nil;
    
    // returns an image description for the GWorlds PixMap
	// on entry the imageDesc is NULL, on return it is correctly filled out
	// you are responsible for disposing it
    err = MakeImageDescriptionForPixMap(hPixMap, &desc);
	if (err)  {	
		if (desc)
			DisposeHandle((Handle)desc);
		return err;
	}
    
    *imageSize = (GetPixRowBytes(hPixMap) * (*desc)->height); // ((**hPixMap).rowBytes & 0x3fff) * (*desc)->height;
	
	// begin the process of decompressing a sequence of frames
	// the destination is the onscreen window
    err = DecompressSequenceBegin(seq,					// pointer to field to receive unique ID for sequence
    							  desc,					// handle to image description structure
    							  pDest,				// port for the DESTINATION image
    							  NULL,					// graphics device handle, if port is set, set to NULL
                                  &bounds,				// source rectangle defining the portion of the image to decompress
                                  NULL,					// transformation matrix
                                  ditherCopy,			// transfer mode specifier
                                  (RgnHandle)NULL,		// clipping region in dest. coordinate system to use as a mask	
                                  0,					// flags
                                  codecNormalQuality,	// accuracy in decompression
                                  bestSpeedCodec);			// compressor identifier or special identifiers ie. bestSpeedCodec
	return 0;
}


// --------------------
// MakeSequenceGrabber
//
SeqGrabComponent MakeSequenceGrabber(WindowRef pWindow)
{
	SeqGrabComponent seqGrab = NULL;
	OSErr			 err = noErr;

    // open the default sequence grabber
    seqGrab = OpenDefaultComponent(SeqGrabComponentType, 0);
    if (seqGrab != NULL) { 
    	// initialize the default sequence grabber component
    	err = SGInitialize(seqGrab);

    	if (err == noErr)
        	// set its graphics world to the specified window
        	err = SGSetGWorld(seqGrab, GetWindowPort(pWindow), NULL );
    	
    	if (err == noErr)
    		// specify the destination data reference for a record operation
    		// tell it we're not making a movie
    		// if the flag seqGrabDontMakeMovie is used, the sequence grabber still calls
    		// your data function, but does not write any data to the movie file
    		// writeType will always be set to seqGrabWriteAppend
    		err = SGSetDataRef(seqGrab,
    						   0,
    						   0,
    						   seqGrabDontMakeMovie);
    }

    if (err && (seqGrab != NULL)) { // clean up on failure
    	CloseComponent(seqGrab);
        seqGrab = NULL;
    }
    
	return seqGrab;
}

// --------------------
// MakeSequenceGrabChannel
//
OSErr MakeSequenceGrabChannel(SeqGrabComponent seqGrab, SGChannel *sgchanVideo, Rect const *rect)
{
    long  flags = 0;
    
    OSErr err = noErr;
    
    err = SGNewChannel(seqGrab, VideoMediaType, sgchanVideo);
    if (err == noErr) {
	    err = SGSetChannelBounds(*sgchanVideo, rect);
	    if (err == noErr)
	    	// set usage for new video channel to avoid playthrough
	   		// note we don't set seqGrabPlayDuringRecord
	    	err = SGSetChannelUsage(*sgchanVideo, flags | seqGrabRecord );
	    
	    if (err != noErr) {
	        // clean up on failure
	        SGDisposeChannel(seqGrab, *sgchanVideo);
	        *sgchanVideo = NULL;
	    }
    }

	return err;
}


#pragma mark Debbuging helpers

// Turns a C array of a number into a string for NSLog
// Sections can be uncommented to print more info about the number
- (NSString *)stringFromArrray:(char [3][12])aNumberArray {		
	
	NSMutableString *numberString = [NSMutableString string];	
	//NSMutableString *sureness = [NSMutableString string];	
	//NSMutableString *evenODD = [NSMutableString string];	
	
	int i;
	for (i = 0; i < 12; i++) {
		int numberValue = aNumberArray[0][i];
		if (numberValue == -1)
			[numberString appendString:@"?"];
		else
			[numberString appendString:[NSString stringWithFormat:@"%d", numberValue]];
		
		//[sureness appendString:[NSString stringWithFormat:@"%d ", aNumberArray[2][i]]];
		//[evenODD appendString:[NSString stringWithFormat:@"%d", aNumberArray[1][i]]];
	}
	
	//	NSLog(@"Number : %@", numberString);
	//	NSLog(@"Surenes: %@ ", sureness);
	//	NSLog(@"evenOdd: %@ ", evenODD);
	
	
	return numberString;
}


- (NSString *)barcodeFromArray:(char [3][12])aNumberArray {
	//It's a UPC don't include the leading zero from the EAN
	if (previousNumberGlobalArray[1][6] == 0)
		return [self stringFromArrray:aNumberArray];
	else
		return [NSString stringWithFormat:@"%d%@", aNumberArray[1][6], [self stringFromArrray:aNumberArray]];	
	
}


- (NSString *)stringFromBars:(int [62])aNumberArray {		
	
	NSMutableString *numberString = [NSMutableString string];	
	int i;
	for (i = 0; i < 62; i++) {
		[numberString appendString:[NSString stringWithFormat:@"%d ", aNumberArray[i]]];
	}
	return numberString;
}

#if DEBUG
- (void)setScanBarcode:(BOOL)aBoolValue {
	scanBarcode = aBoolValue;
}


#pragma mark Experimental

//Experimentation with finding out the distance between peaks as they are not as sucetible to blurring 
 - (void)getPeakDistance:(int [62])barsArrayOneDimension forLine:(int *)pixelLineArray start:(int)startBarcode end:(int)endBarcode {
	 
	 BOOL goingUp = NO;
	 int index = startBarcode;
	 int count = 0;
	 int peakNumber = 0;
	 int smallestWidth = 200;
	 
	 NSBezierPath *aPath = [NSBezierPath bezierPath];
	 
	 //Prime to the first peak
	 while (pixelLineArray[index +1] - pixelLineArray[index] > 0){
		 index++;
	 }
	 
	 [aPath moveToPoint:NSMakePoint(index, 255)];
	 [aPath lineToPoint:NSMakePoint(index, 0)];
	 
	 while (index < endBarcode) {
		 
		 int delta = pixelLineArray[index +1] - pixelLineArray[index];
		 
		 //going up hill mark it
		 if (delta > -4) {  //A -4 delta also aovid noise 
			 goingUp = YES;
		 }
		 else if (goingUp) { //going down after going up mark as peak
			 
			 
			 //Noise Reduction peaks should't be 1 or 2 away only
			 if (count > 2) {
				 
				 [aPath moveToPoint:NSMakePoint(index, 255)];
				 [aPath lineToPoint:NSMakePoint(index, 0)];
				 
				 barsArrayOneDimension[peakNumber] = count;
				 
				 if (count < smallestWidth)
					 smallestWidth = count;
				 
				 peakNumber++;
				 count = 0;
				 goingUp = NO;
			 }
		 }
		 
		 count++;
		 index++;
	 }
	 
	 
	 NSMutableString *numberString = [NSMutableString string];	
	 int i;
	 for (i = 0; i < peakNumber; i++) {
		 [numberString appendString:[NSString stringWithFormat:@"%d ", barsArrayOneDimension[i]]];
	 }
	 NSLog(@"Peaks: %@", numberString);
	 
	 
	 
	 //Normalize
	 float averageCount = barsArrayOneDimension[0];
	 float normalize[62] = {0};
	 numberString = [NSMutableString string];	
	 for (i = 0; i < peakNumber; i++) {
		 //normalize[i] = (float)barsArrayOneDimension[i] / (float)smallestWidth;
		 normalize[i] = (float)barsArrayOneDimension[i] / averageCount;
		 [numberString appendString:[NSString stringWithFormat:@"%f ", normalize[i]]];
	 }
	 NSLog(@"Normalize: %@", numberString);
	 
	 
	 [graphView setRedPath:aPath];
	 
	 
	 
 }

#endif DEBUG

@end
