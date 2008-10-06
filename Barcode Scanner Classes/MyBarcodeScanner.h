/*
 MyBarcodeScanner.m is part of BarcodeScanner.
 
 BarcodeScanner is free software; you can redistribute it and/or modify
 it under the terms of the The MIT License
 
 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

/*
	File  MyBarcodeScanner.m is based on the sample file SonOfMunggrab.c from Apple SGDataProcSample
	
	Description: This example shows how to run the Sequence Grabber in record mode and use
 a DataProc to get and modify the captured data. SonOfMunggrab calculates the
 frame rate using the time value stamp passed to the data proc then draws this
 rate onto the frame. This technique provides optimal performance, far better
 than using preview mode or bottlenecks. This code will help a lot when
 capturing from DV and should allow 30fps playthrough using DV capture on a G3.
 
 SonOfMunggrab is the offspring of Munggrab written by the illustrious
 Kevin Marks. While the techniques presented in the original Munggrab remain
 the same, this sample throws Carbon Events into the fray for better performance
 on Mac OS X.
 
	Author:		km, era
 
	Copyright: 	ｩ Copyright 2000 - 2001 Apple Computer, Inc. All rights reserved.
	
	Disclaimer:	IMPORTANT:  This Apple software is supplied to you by Apple Computer, Inc.
 ("Apple") in consideration of your agreement to the following terms, and your
 use, installation, modification or redistribution of this Apple software
 constitutes acceptance of these terms.  If you do not agree with these terms,
 please do not use, install, modify or redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and subject
 to these terms, Apple grants you a personal, non-exclusive license, under Appleﾕs
 copyrights in this original Apple software (the "Apple Software"), to use,
 reproduce, modify and redistribute the Apple Software, with or without
 modifications, in source and/or binary forms; provided that if you redistribute
 the Apple Software in its entirety and without modifications, you must retain
 this notice and the following text and disclaimers in all such redistributions of
 the Apple Software.  Neither the name, trademarks, service marks or logos of
 Apple Computer, Inc. may be used to endorse or promote products derived from the
 Apple Software without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or implied,
 are granted by Apple herein, including but not limited to any patent rights that
 may be infringed by your derivative works or by other works in which the Apple
 Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE MAKES NO
 WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION THE IMPLIED
 WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND OPERATION ALONE OR IN
 COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL OR
 CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
						GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION, MODIFICATION AND/OR DISTRIBUTION
 OF THE APPLE SOFTWARE, HOWEVER CAUSED AND WHETHER UNDER THEORY OF CONTRACT, TORT
 (INCLUDING NEGLIGENCE), STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
	Change History (most recent first): <3> 3/28/02 DV source rect bug fix in DataProc
 <2> 7/08/01 carbonized and born as SonOfMunggrab
 <1> 1/13/00 initial release
 
 */


/*
	A possible confusing aspect of the code is the use of  #DEBUG
	The code behaves differently when compiled under the Debug build configuration than the release
	DEBUG is defined in the other C Flags of the build rules at the target level.
	Keep in mind that during DEBUG the iSight window needs to be clicked with the mouse or the enter key pressed
	for a barcode scan to take place.
 */

#import <Cocoa/Cocoa.h>
@class MyiSightWindow;

//Protocol for those that use the barcode scanning, in this case MyController
@protocol BarcodeScanning
- (bool)gotBarcode:(NSString *)barcode;
@end

@interface NSObject (BarcodeScanningProtocolOptional)
- (void)iSightWillClose;
@end


@interface MyBarcodeScanner : NSObject {
	@private
	
	id delegate;
	NSTimer *idleTimer;
	MyiSightWindow *iSightWindow;
	NSString *lastBarcode;
	BOOL stayOpen;
	int numberOfDigitsFound;
  
  NSString *soudName;

	/*
		These arrays hold possible barcode numbers. 
		The first row holds the possible digit for each of the 12 locations
		The second row holds if the number was even or odd decoded (This is information is present for the first 6 numbers, the last six have the same encoding)
		The 7th number on the second row holds the 13th digit; that whcih the previous 6 odd/even encodings combination represents. 
		The third row holds a number indicating the degree of sureness for that number, depending on how many times it was scanned.
	 */
	char previousNumberGlobalArray[3][12],  previousNumberLocalArray[3][12], numberArray[3][12];
		
	//Use to limit the barcode scanning to only happening with a mouse click
#if DEBUG
	BOOL scanBarcode;
#endif DEBUG

}

//Singleton
+ (MyBarcodeScanner *)sharedInstance;

- (void)scanForBarcodeWindow:(NSWindow *)callingWindow;

- (void)setDelegate:(id)aDelegate;
- (void)setStaysOpen:(BOOL)stayOpenValue;
- (void)setMirrored:(BOOL)mirroredValue;

#if DEBUG
- (void)setScanBarcode:(BOOL)aBoolValue;
#endif DEBUG

//Window delegate
- (void)windowWillClose:(NSNotification *)aNotification;

@end

