//
//  MyGraphView.m

#import "MyGraphView.h"


@implementation MyGraphView

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (void) dealloc {
	[greenPath release];
	[redPath release];
	[bluePath release];
	[super dealloc];
}


- (void)drawRect:(NSRect)rect {
    // Drawing code here.
 	[[NSColor whiteColor] set];
	[NSBezierPath fillRect:rect];
	
	[[NSColor greenColor] set];
	[greenPath stroke];
	
	[[NSColor redColor] set];
	[redPath stroke];
	
	[[NSColor blueColor] set];
	[bluePath stroke];
}

- (void)setGreenPath:(NSBezierPath *)aPath {
	[greenPath release];
	greenPath = [aPath retain];
[self setNeedsDisplay:YES];
}

- (void)setRedPath:(NSBezierPath *)aPath {
	[redPath release];
	redPath = [aPath retain];
	[self setNeedsDisplay:YES];
}

- (void)setBluePath:(NSBezierPath *)aPath {
	[bluePath release];
	bluePath = [aPath retain];
[self setNeedsDisplay:YES];
}


@end
