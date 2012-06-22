//
//  SLPaperView.m
//  Paper Stack
//
//  Created by Adam Wulf on 6/8/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "SLPaperView.h"
#import <QuartzCore/QuartzCore.h>
#import "NSArray+MapReduce.h"

@implementation SLPaperView

@synthesize scale;
@synthesize delegate;
@synthesize isBeingPannedAndZoomed;
@synthesize textLabel;
@synthesize isBrandNewPage;

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code
        UIImage* img = [UIImage imageNamed:[NSString stringWithFormat:@"img0%d.jpg", rand() % 6 + 1]];
        UIImageView* imgView = [[[UIImageView alloc] initWithImage:img] autorelease];
        imgView.frame = self.bounds;
        imgView.contentMode = UIViewContentModeScaleAspectFill;
        imgView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        imgView.clipsToBounds = YES;
        [self addSubview:imgView];
        
        [self.layer setMasksToBounds:YES ];
        [self.layer setBorderColor:[[[UIColor blackColor] colorWithAlphaComponent:.5] CGColor ] ];
        [self.layer setBorderWidth:1.0];

        preGestureScale = 1;
        scale = 1;
        
        panGesture = [[[SLBezelOutPanPinchGestureRecognizer alloc] 
                                               initWithTarget:self 
                                                      action:@selector(panAndScale:)] autorelease];
        [panGesture setMinimumNumberOfTouches:2];
        panGesture.bezelDirectionMask = SLBezelDirectionRight;
        [self addGestureRecognizer:panGesture];

    /*
        textLabel = [[[UILabel alloc] initWithFrame:CGRectMake(20, 20, 400, 40)] autorelease];
        textLabel.backgroundColor = [UIColor whiteColor];
        textLabel.textColor = [UIColor blackColor];
        [self addSubview:textLabel];
     */
    }
    return self;
}

-(BOOL) willExitBezel{
    BOOL isRight = (panGesture.didExitToBezel & SLBezelDirectionRight) == SLBezelDirectionRight;
    return isRight && panGesture.state == UIGestureRecognizerStateChanged;
}

-(void) cancelAllGestures{
    for(UIGestureRecognizer* gesture in self.gestureRecognizers){
        if([gesture respondsToSelector:@selector(cancel)]){
            [(SLBezelOutPanPinchGestureRecognizer*)gesture cancel];
        }
    }
}
-(void) disableAllGestures{
    for(UIGestureRecognizer* gesture in self.gestureRecognizers){
        [gesture setEnabled:NO];
    }
    textLabel.text = @"disabled";
}
-(void) enableAllGestures{
    for(UIGestureRecognizer* gesture in self.gestureRecognizers){
        [gesture setEnabled:YES];
    }
    textLabel.text = @"enabled";
}


/**
 * this is the heart of the two finger zoom/pan for pages
 *
 * the premise is:
 *
 * a) if two fingers are down, then pan and zoom
 * b) if the user lifts a finger, then stop all motion, but don't yield to any other gesture
 *      (ios default is to continue the gesture altogether. instead we'll stop the gesture, but still won't yeild)
 * c) the zoom should zoom into the location of the zoom gesture. don't just zoom from top/left or center
 * d) lock zoom at .7x > 2x
 * e) call delegates to ask if panning or zoom should even be enabled
 * f) call delegates to ask them to perform any other modifications to the frame before setting it to the page
 * g) notify the delegate when the pan and zoom is complete
 *
 * TODO
 * its possible using 3+ fingers to have the page suddenly fly offscreen
 * i should possibly cap the speed that the page can move just like i do with scale,
 * and also should ensure it never goes offscreen. there's no reason to show less than 100px
 * in any direction (maybe more).
 */
-(void) panAndScale:(SLBezelOutPanPinchGestureRecognizer*)_panGesture{
    CGPoint panDiffLocation = [panGesture translationInView:self];
    CGPoint lastLocationInSelf = [panGesture locationInView:self];
    CGPoint velocity = [self calculateVelocityOfPanGesture:panGesture withTranslation:panDiffLocation];
    if(panGesture.state == UIGestureRecognizerStateCancelled ||
       panGesture.state == UIGestureRecognizerStateEnded ||
       panGesture.state == UIGestureRecognizerStateFailed){
        [self.delegate finishedPanningAndScalingPage:self 
                                           intoBezel:panGesture.didExitToBezel
                                           fromFrame:frameOfPageAtBeginningOfGesture
                                             toFrame:self.frame
                                        withVelocity:velocity];
        isBeingPannedAndZoomed = NO;
        return;
    }else if(panGesture.numberOfTouches == 1){
        if(lastNumberOfTouchesForPanGesture != 1){
            // notify the delegate of our state change
            [self.delegate isPanningAndScalingPage:self
                                         fromFrame:frameOfPageAtBeginningOfGesture
                                           toFrame:frameOfPageAtBeginningOfGesture];
        }
        //
        // the gesture requires 2 fingers. it may still say it only has 1 touch if the user
        // started the gesture with 2 fingers but then lifted a finger. in that case, 
        // don't continue the gesture at all, just wait till they finish it proper or re-put
        // that 2nd touch down
        lastNumberOfTouchesForPanGesture = 1;
        isBeingPannedAndZoomed = NO;
        return;
    }else if(lastNumberOfTouchesForPanGesture == 1 ||
             panGesture.state == UIGestureRecognizerStateBegan){
        isBeingPannedAndZoomed = YES;
        //
        // if the user had 1 finger down and re-touches with the 2nd finger, then this
        // will be called as if it was a "new" gesture. this lets the pan and zoom start
        // from the correct new gesture are of the page.
        //
        // to test. begin pan/zoom in bottom left, then lift 1 finger and move to the top right
        // of the page, then re-pan/zoom on the top right. it should "just work".
        
        // Reset Panning
        // ====================================================================================
        // we know a valid gesture has 2 touches down
        lastNumberOfTouchesForPanGesture = 2;
        // find the location of the first touch in relation to the superview.
        // since the superview doesn't move, this'll give us a static coordinate system to
        // measure panning distance from
        firstLocationOfPanGestureInSuperView = [panGesture locationInView:self.superview];
        // note the origin of the frame before the gesture begins.
        // all adjustments of panning/zooming will be offset from this origin.
        frameOfPageAtBeginningOfGesture = self.frame;
        
        // Reset Scaling
        // ====================================================================================
        // remember the scale of the view before the gesture begins. we'll normalize the gesture's
        // scale value to the superview location by multiplying it to the page's current scale
        preGestureScale = self.scale;
        // the normalized location of the gesture is (0 < x < 1, 0 < y < 1).
        // this lets us locate where the gesture should be in the view from any width or height
        normalizedLocationOfScale = CGPointMake(lastLocationInSelf.x / self.frame.size.width, 
                                                lastLocationInSelf.y / self.frame.size.height);
        return;
    }
    
    
    //
    // to track panning, we collect the first location of the pan gesture, and calculate the offset
    // of the current location of the gesture. that distance is the amount moved for the pan.
//    panDiffLocation = CGPointMake(lastLocationInSuperview.x - firstLocationOfPanGestureInSuperView.x, lastLocationInSuperview.y - firstLocationOfPanGestureInSuperView.y);
    
    if([self.delegate allowsScaleForPage:self]){
        
        CGFloat gestureScale = panGesture.scale;
        CGFloat targetScale = preGestureScale * gestureScale;
//        if(targetScale > 1){
//            targetScale = roundf(targetScale * 2) / 2;
//        }
        
        //
        // to track scaling, the scale value has to be a value between .7 and 2.0x of the /superview/'s size
        // if i begin scaling an already zoomed in page, the gesture's default is the re-begin the zoom at 1.0x
        // even though it may be 2x of our page size. so we need to remember the current scale in preGestureScale
        // and multiply that by the gesture's scale value. this gives us the scale value as a factor of the superview
        if(targetScale > 2.5){
            // 2.0 is the maximum
            scale = 2.5;
        }else if(targetScale < 0.75){
            // 0.75 is zoom minimum
            scale = 0.75;
        }else if(ABS((float)(targetScale - scale)) > .01){
            //
            // TODO
            // only update the scale if its greater than a 1% difference of the previous
            // scale. the goal here is to optimize re-draws for the view, but this should be
            // validated when the full page contents are implemented.
            if(scale < targetScale && scale > targetScale - .05){
                scale = targetScale;
            }else if(scale < targetScale){
                scale += (targetScale - scale) / 5;
            }else if(scale > targetScale && scale < targetScale + .05){
                scale = targetScale;
            }else if(scale > targetScale){
                scale -= (scale - targetScale) / 5;
            }
//            scale = targetScale;
        }
    }
    
    //
    // now, with our pan offset and new scale, we need to calculate the new frame location.
    //
    // first, find the location of the gesture at the size of the page before the gesture began.
    // then, find the location of the gesture at the new scale of the page.
    // since we're using the normalized location of the gesture, this will make sure the before/after
    // location of the gesture is in the same place of the view after scaling the width/height.
    // the difference in these locations is how muh we need to move the origin of the page to
    // accomodate the new scale while maintaining the location of the gesture uner the user's fingers
    //
    // the, add the diff of the pan gesture to get the full displacement of the origin. also set the 
    // width and height to the new scale.
    CGSize superviewSize = self.superview.bounds.size;
    CGPoint locationOfPinchBeforeScale = CGPointMake(preGestureScale * normalizedLocationOfScale.x * superviewSize.width,
                                                     preGestureScale * normalizedLocationOfScale.y * superviewSize.height);
    CGPoint locationOfPinchAfterScale = CGPointMake(scale * normalizedLocationOfScale.x * superviewSize.width,
                                                    scale * normalizedLocationOfScale.y * superviewSize.height);
    CGPoint adjustmentForScale = CGPointMake((locationOfPinchAfterScale.x - locationOfPinchBeforeScale.x),
                                             (locationOfPinchAfterScale.y - locationOfPinchBeforeScale.y));
    CGSize newSizeOfView = CGSizeMake(superviewSize.width * scale, superviewSize.height * scale);

    
    //
    // now calculate our final frame given our pan and zoom
    CGRect fr = self.frame;
    fr.origin = CGPointMake(frameOfPageAtBeginningOfGesture.origin.x + panDiffLocation.x - adjustmentForScale.x,
                            frameOfPageAtBeginningOfGesture.origin.y + panDiffLocation.y - adjustmentForScale.y);
    fr.size = newSizeOfView;
    
    //
    // now, notify delegate that we're about to set the frame of the page during a gesture,
    // and give it a chance to modify the frame if at all needed.
    fr = [self.delegate isPanningAndScalingPage:self
                      fromFrame:frameOfPageAtBeginningOfGesture
                        toFrame:fr];
    
    
    //
    // now we're ready, set the frame!
    self.frame = fr;
    
}




/**
 * this function processes each step of the pan gesture, and uses
 * it to caclulate the velocity when the user lifts their finger.
 *
 * we use this to have the paper slide when the user swipes quickly
 */
- (CGPoint)calculateVelocityOfPanGesture:(UIPanGestureRecognizer *)sender withTranslation:(CGPoint)translate
{
//    CGPoint translate = [sender translationInView:self];
    static NSTimeInterval lastTime;
    static NSTimeInterval currTime;
    static CGPoint currTranslate;
    static CGPoint lastTranslate;
    
    if (sender.state == UIGestureRecognizerStateBegan)
    {
        currTime = [NSDate timeIntervalSinceReferenceDate];
        currTranslate = translate;
    }
    else if (sender.state == UIGestureRecognizerStateChanged)
    {
        lastTime = currTime;
        lastTranslate = currTranslate;
        currTime = [NSDate timeIntervalSinceReferenceDate];
        currTranslate = translate;
    }   
    else if (sender.state == UIGestureRecognizerStateEnded)
    {
        if (lastTime)
        {
            NSTimeInterval seconds = [NSDate timeIntervalSinceReferenceDate] - lastTime;
            if (seconds){
                return CGPointMake((translate.x - lastTranslate.x) / seconds, (translate.y - lastTranslate.y) / seconds);
            }
        }
        /*
         // let's calculate where that flick would take us this far in the future
        float inertiaSeconds = 1.0;
        CGPoint final = CGPointMake(translate.x + swipeVelocity.x * inertiaSeconds, translate.y + swipeVelocity.y * inertiaSeconds);
         */
        
    }
    return CGPointZero;
}


@end
