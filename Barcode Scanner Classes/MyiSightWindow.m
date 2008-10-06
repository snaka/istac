//
//  MyiSightWindow.m

#import "MyiSightWindow.h"
#import "MyBarcodeScanner.h"


@implementation MyiSightWindow


- (BOOL)canBecomeKeyWindow {
	return YES;
}


- (BOOL)performKeyEquivalent:(NSEvent *)theEvent {
	unichar characterHit = [[theEvent characters] characterAtIndex:0];
	if ( characterHit == 27 || characterHit == 32 || characterHit == 127 || characterHit == 46) { //esc, delete, period
		[self close];
		return YES;
	}
#if DEBUG
	else if (characterHit == 13) { //enter
		[[self delegate] setScanBarcode:YES];
		return YES;
	}
#endif DEBUG

	
	return NO;
}

#if DEBUG
- (void)mouseDown:(NSEvent *)theEvent {
	[[self delegate] setScanBarcode:YES];
	[super mouseDown:theEvent];
}
#endif DEBUG


@end
