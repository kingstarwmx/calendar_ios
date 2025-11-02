//
//  FSCalendarTransitionCoordinator.m
//  FSCalendar
//
//  Created by Wenchao Ding on 3/13/16.
//  Copyright © 2016 Wenchao Ding. All rights reserved.
//

#import "FSCalendarTransitionCoordinator.h"
#import "FSCalendarExtensions.h"
#import "FSCalendarDynamicHeader.h"
#import <objc/runtime.h>

@interface FSCalendar (MaxHeightTransition)
- (BOOL)canTransitionToMaxHeight;
- (CGFloat)effectiveMaxRowHeight;
- (CGFloat)baselineRowHeight;
@end

@interface FSCalendarTransitionCoordinator ()

@property (weak, nonatomic) FSCalendarCollectionView *collectionView;
@property (weak, nonatomic) FSCalendarCollectionViewLayout *collectionViewLayout;
@property (weak, nonatomic) FSCalendar *calendar;

@property (strong, nonatomic) FSCalendarTransitionAttributes *transitionAttributes;
@property (strong, nonatomic) CADisplayLink *displayLink;

- (FSCalendarTransitionAttributes *)createTransitionAttributesTargetingScope:(FSCalendarScope)targetScope;
- (FSCalendarTransitionAttributes *)createTransitionAttributesFromScope:(FSCalendarScope)sourceScope toScope:(FSCalendarScope)targetScope;
- (FSCalendarScope)normalizedScope:(FSCalendarScope)scope;
- (BOOL)requiresAlphaAnimationForAttributes:(FSCalendarTransitionAttributes *)attributes;
- (BOOL)requiresCollectionOffsetForAttributes:(FSCalendarTransitionAttributes *)attributes;

- (void)performTransitionCompletionAnimated:(BOOL)animated;

- (void)performAlphaAnimationWithProgress:(CGFloat)progress;
- (void)performPathAnimationWithProgress:(CGFloat)progress;

- (void)scopeTransitionDidBegin:(UIPanGestureRecognizer *)panGesture;
- (void)scopeTransitionDidUpdate:(UIPanGestureRecognizer *)panGesture;
- (void)scopeTransitionDidEnd:(UIPanGestureRecognizer *)panGesture;

- (void)boundingRectWillChange:(CGRect)targetBounds animated:(BOOL)animated;

@end

@implementation FSCalendarTransitionCoordinator

- (instancetype)initWithCalendar:(FSCalendar *)calendar
{
    self = [super init];
    if (self) {
        self.calendar = calendar;
        self.collectionView = self.calendar.collectionView;
        self.collectionViewLayout = self.calendar.collectionViewLayout;
    }
    return self;
}

#pragma mark - Target actions

- (void)handleScopeGesture:(UIPanGestureRecognizer *)sender
{
    switch (sender.state) {
        case UIGestureRecognizerStateBegan: {
            [self scopeTransitionDidBegin:sender];
            break;
        }
        case UIGestureRecognizerStateChanged: {
            [self scopeTransitionDidUpdate:sender];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:{
            [self scopeTransitionDidEnd:sender];
            break;
        }
        default: {
            break;
        }
    }
}

#pragma mark - <UIGestureRecognizerDelegate>

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    if (self.state != FSCalendarTransitionStateIdle) {
        return NO;
    }
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    
    if (gestureRecognizer == self.calendar.scopeGesture && self.calendar.collectionViewLayout.scrollDirection == UICollectionViewScrollDirectionVertical) {
        return NO;
    }
    if ([gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]] && [[gestureRecognizer valueForKey:@"_targets"] containsObject:self.calendar]) {
        CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:gestureRecognizer.view];
        BOOL shouldStart = NO;
        switch (self.calendar.scope) {
            case FSCalendarScopeWeek:
                shouldStart = velocity.y >= 0.0f;
                break;
            case FSCalendarScopeMonth:
                if (velocity.y < 0.0f) {
                    shouldStart = YES;
                } else if (velocity.y > 0.0f) {
                    shouldStart = [self.calendar canTransitionToMaxHeight];
                }
                break;
            case FSCalendarScopeMaxHeight:
                shouldStart = velocity.y <= 0.0f;
                break;
        }
        if (!shouldStart) return NO;
        shouldStart = (ABS(velocity.x) <= ABS(velocity.y));
        if (shouldStart) {
            self.calendar.collectionView.panGestureRecognizer.enabled = NO;
            self.calendar.collectionView.panGestureRecognizer.enabled = YES;
        }
        return shouldStart;
    }
    return YES;
    
#pragma GCC diagnostic pop
    
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return otherGestureRecognizer == self.collectionView.panGestureRecognizer && self.collectionView.decelerating;
}

- (void)scopeTransitionDidBegin:(UIPanGestureRecognizer *)panGesture
{
    if (self.state != FSCalendarTransitionStateIdle) return;
    
    CGPoint velocity = [panGesture velocityInView:panGesture.view];
    FSCalendarScope sourceScope = self.calendar.scope;
    FSCalendarScope targetScope = sourceScope;
    if (sourceScope == FSCalendarScopeMonth) {
        if (velocity.y < 0.0f) {
            targetScope = FSCalendarScopeWeek;
        } else if (velocity.y > 0.0f && [self.calendar canTransitionToMaxHeight]) {
            targetScope = FSCalendarScopeMaxHeight;
        }
    } else if (sourceScope == FSCalendarScopeWeek) {
        if (velocity.y > 0.0f) {
            targetScope = FSCalendarScopeMonth;
        }
    } else if (sourceScope == FSCalendarScopeMaxHeight) {
        if (velocity.y < 0.0f) {
            targetScope = FSCalendarScopeMonth;
        }
    }
    if (targetScope == sourceScope) {
        return;
    }

    self.state = FSCalendarTransitionStateChanging;
    self.transitionAttributes = [self createTransitionAttributesFromScope:sourceScope toScope:targetScope];
    
    if (self.transitionAttributes.sourceScope == FSCalendarScopeWeek && self.transitionAttributes.targetScope == FSCalendarScopeMonth) {
        [self prepareWeekToMonthTransition];
    }
}

- (void)scopeTransitionDidUpdate:(UIPanGestureRecognizer *)panGesture
{
    if (self.state != FSCalendarTransitionStateChanging) return;

    FSCalendarTransitionAttributes *attr = self.transitionAttributes;

    // 检测方向变化：如果当前sourceScope是Month，根据translationY重新确定targetScope
    CGFloat translationY = [panGesture translationInView:panGesture.view].y;
    if (attr.sourceScope == FSCalendarScopeMonth) {
        FSCalendarScope newTargetScope = attr.targetScope;

        if (translationY < 0) {
            // 往上滑，应该到Week
            newTargetScope = FSCalendarScopeWeek;
        } else if (translationY > 0 && [self.calendar canTransitionToMaxHeight]) {
            // 往下滑，应该到MaxHeight
            newTargetScope = FSCalendarScopeMaxHeight;
        }

        // 如果目标发生了变化，重新创建transitionAttributes
        if (newTargetScope != attr.targetScope) {
            printf("🔄 方向改变: %ld -> %ld\n", (long)attr.targetScope, (long)newTargetScope);
            self.transitionAttributes = [self createTransitionAttributesFromScope:attr.sourceScope toScope:newTargetScope];
            attr = self.transitionAttributes;
        }
    }

    BOOL involvesMax = (attr.sourceScope == FSCalendarScopeMaxHeight || attr.targetScope == FSCalendarScopeMaxHeight);
    if (!involvesMax) {
        CGFloat translation = ABS([panGesture translationInView:panGesture.view].y);
        CGFloat progress = ({
            CGFloat maxTranslation = ABS(CGRectGetHeight(attr.targetBounds) - CGRectGetHeight(attr.sourceBounds));
            translation = MIN(maxTranslation, translation);
            translation = MAX(0, translation);
            CGFloat progress = maxTranslation > 0 ? translation/maxTranslation : 0;
            progress;
        });
        [self performAlphaAnimationWithProgress:progress];
        [self performPathAnimationWithProgress:progress];
        return;
    }

    CGFloat deltaHeight = CGRectGetHeight(attr.targetBounds) - CGRectGetHeight(attr.sourceBounds);
    CGFloat direction = deltaHeight >= 0 ? 1.0f : -1.0f;
    CGFloat directedTranslation = translationY * direction;
    CGFloat maxTranslation = ABS(deltaHeight);
    directedTranslation = MIN(MAX(directedTranslation, 0.0f), maxTranslation);
    CGFloat progress = maxTranslation > 0.0f ? directedTranslation / maxTranslation : 0.0f;
    [self performAlphaAnimationWithProgress:progress];
    [self performPathAnimationWithProgress:progress];
}

- (void)scopeTransitionDidEnd:(UIPanGestureRecognizer *)panGesture
{
    if (self.state != FSCalendarTransitionStateChanging) return;
    
    self.state = FSCalendarTransitionStateFinishing;

    FSCalendarTransitionAttributes *attr = self.transitionAttributes;
    BOOL involvesMax = (attr.sourceScope == FSCalendarScopeMaxHeight || attr.targetScope == FSCalendarScopeMaxHeight);
    if (!involvesMax) {
        CGFloat translation = [panGesture translationInView:panGesture.view].y;
        CGFloat velocity = [panGesture velocityInView:panGesture.view].y;
        CGFloat progress = ({
            CGFloat maxTranslation = CGRectGetHeight(attr.targetBounds) - CGRectGetHeight(attr.sourceBounds);
            translation = MAX(0, translation);
            translation = MIN(maxTranslation, translation);
            CGFloat progress = maxTranslation > 0 ? translation/maxTranslation : 1.0f;
            progress;
        });
        if (velocity * translation < 0) {
            [attr revert];
        }
        [self performTransition:attr.targetScope fromProgress:progress toProgress:1.0 animated:YES];
        return;
    }

    CGFloat translationY = [panGesture translationInView:panGesture.view].y;
    CGFloat velocityY = [panGesture velocityInView:panGesture.view].y;
    CGFloat deltaHeight = CGRectGetHeight(attr.targetBounds) - CGRectGetHeight(attr.sourceBounds);
    CGFloat direction = deltaHeight >= 0 ? 1.0f : -1.0f;
    CGFloat directedTranslation = translationY * direction;
    CGFloat directedVelocity = velocityY * direction;
    CGFloat maxTranslation = ABS(deltaHeight);
    directedTranslation = MIN(MAX(directedTranslation, 0.0f), maxTranslation);
    CGFloat progress = maxTranslation > 0.0f ? directedTranslation / maxTranslation : 1.0f;
    if (directedVelocity < 0.0f) {
        [attr revert];
    }
    [self performTransition:attr.targetScope fromProgress:progress toProgress:1.0f animated:YES];
}

#pragma mark - Public methods

- (void)performScopeTransitionFromScope:(FSCalendarScope)fromScope toScope:(FSCalendarScope)toScope animated:(BOOL)animated
{
    if (fromScope == toScope) {
        [self.calendar willChangeValueForKey:@"scope"];
        [self.calendar fs_setUnsignedIntegerVariable:toScope forKey:@"_scope"];
        [self.calendar didChangeValueForKey:@"scope"];
        return;
    }
    // Start transition
    self.state = FSCalendarTransitionStateFinishing;
    FSCalendarTransitionAttributes *attr = [self createTransitionAttributesFromScope:fromScope toScope:toScope];
    self.transitionAttributes = attr;
    if (fromScope == FSCalendarScopeWeek && toScope == FSCalendarScopeMonth) {
        [self prepareWeekToMonthTransition];
    }
    [self performTransition:self.transitionAttributes.targetScope fromProgress:0 toProgress:1 animated:animated];
}

- (void)performBoundingRectTransitionFromMonth:(NSDate *)fromMonth toMonth:(NSDate *)toMonth duration:(CGFloat)duration
{
    if (!self.calendar.adjustsBoundingRectWhenChangingMonths) return;
    if (self.calendar.scope != FSCalendarScopeMonth) return;
    NSInteger lastRowCount = [self.calendar.calculator numberOfRowsInMonth:fromMonth];
    NSInteger currentRowCount = [self.calendar.calculator numberOfRowsInMonth:toMonth];
    if (lastRowCount != currentRowCount) {
        CGFloat animationDuration = duration;
        CGRect bounds = [self boundingRectForScope:FSCalendarScopeMonth page:toMonth];
        self.state = FSCalendarTransitionStateChanging;
        void (^completion)(BOOL) = ^(BOOL finished) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(0, duration-animationDuration) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                self.calendar.needsAdjustingViewFrame = YES;
                [self.calendar setNeedsLayout];
                self.state = FSCalendarTransitionStateIdle;
            });
        };
        if (FSCalendarInAppExtension) {
            // Detect today extension: http://stackoverflow.com/questions/25048026/ios-8-extension-how-to-detect-running
            [self boundingRectWillChange:bounds animated:YES];
            completion(YES);
        } else {
            [UIView animateWithDuration:animationDuration delay:0  options:UIViewAnimationOptionAllowUserInteraction animations:^{
                [self boundingRectWillChange:bounds animated:YES];
            } completion:completion];
        }
        
    }
}

#pragma mark - Private properties

- (void)performTransitionCompletionAnimated:(BOOL)animated
{
    switch (self.transitionAttributes.targetScope) {
        case FSCalendarScopeWeek: {
            self.collectionViewLayout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
            self.calendar.calendarHeaderView.scrollDirection = self.collectionViewLayout.scrollDirection;
            self.calendar.needsAdjustingViewFrame = YES;
            [self.collectionView reloadData];
            [self.calendar.calendarHeaderView reloadData];
            break;
        }
        case FSCalendarScopeMonth: {
            self.calendar.needsAdjustingViewFrame = YES;
            if (self.transitionAttributes.sourceScope == FSCalendarScopeMaxHeight) {
                self.collectionViewLayout.scrollDirection = (UICollectionViewScrollDirection)self.calendar.scrollDirection;
                self.calendar.calendarHeaderView.scrollDirection = self.collectionViewLayout.scrollDirection;
                self.collectionView.fs_top = 0.0f;
            }
            break;
        }
        case FSCalendarScopeMaxHeight: {
            self.calendar.needsAdjustingViewFrame = YES;
            self.collectionViewLayout.scrollDirection = (UICollectionViewScrollDirection)self.calendar.scrollDirection;
            self.calendar.calendarHeaderView.scrollDirection = self.collectionViewLayout.scrollDirection;
            self.collectionView.fs_top = 0.0f;
            break;
        }
        default:
            break;
    }
    self.state = FSCalendarTransitionStateIdle;
    self.transitionAttributes = nil;
    [self.calendar setNeedsLayout];
    [self.calendar layoutIfNeeded];
}

- (FSCalendarTransitionAttributes *)createTransitionAttributesTargetingScope:(FSCalendarScope)targetScope
{
    FSCalendarTransitionAttributes *attributes = [[FSCalendarTransitionAttributes alloc] init];
    attributes.sourceBounds = self.calendar.bounds;
    attributes.sourcePage = self.calendar.currentPage;
    attributes.targetScope = targetScope;
    attributes.focusedDate = ({
        NSArray<NSDate *> *candidates = ({
            NSMutableArray *dates = self.calendar.selectedDates.reverseObjectEnumerator.allObjects.mutableCopy;
            if (self.calendar.today) {
                [dates addObject:self.calendar.today];
            }
            if (targetScope == FSCalendarScopeWeek) {
                [dates addObject:self.calendar.currentPage];
            } else {
                [dates addObject:[self.calendar.gregorian dateByAddingUnit:NSCalendarUnitDay value:3 toDate:self.calendar.currentPage options:0]];
            }
            dates.copy;
        });
        NSArray<NSDate *> *visibleCandidates = [candidates filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDate *  _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
            NSIndexPath *indexPath = [self.calendar.calculator indexPathForDate:evaluatedObject scope:1-targetScope];
            NSInteger currentSection = [self.calendar.calculator indexPathForDate:self.calendar.currentPage scope:1-targetScope].section;
            return indexPath.section == currentSection;
        }]];
        NSDate *date = visibleCandidates.firstObject;
        date;
    });
    attributes.focusedRow = ({
        NSIndexPath *indexPath = [self.calendar.calculator indexPathForDate:attributes.focusedDate scope:FSCalendarScopeMonth];
        FSCalendarCoordinate coordinate = [self.calendar.calculator coordinateForIndexPath:indexPath];
        coordinate.row;
    });
    attributes.targetPage = ({
        NSDate *targetPage = targetScope == FSCalendarScopeMonth ? [self.calendar.gregorian fs_firstDayOfMonth:attributes.focusedDate] : [self.calendar.gregorian fs_middleDayOfWeek:attributes.focusedDate];
        targetPage;
    });
    attributes.targetBounds = [self boundingRectForScope:attributes.targetScope page:attributes.targetPage];
    return attributes;
}

- (FSCalendarTransitionAttributes *)createTransitionAttributesFromScope:(FSCalendarScope)sourceScope toScope:(FSCalendarScope)targetScope
{
    if (sourceScope != FSCalendarScopeMaxHeight && targetScope != FSCalendarScopeMaxHeight) {
        FSCalendarTransitionAttributes *attributes = [self createTransitionAttributesTargetingScope:targetScope];
        attributes.sourceScope = sourceScope;
        return attributes;
    }

    FSCalendarTransitionAttributes *attributes = [[FSCalendarTransitionAttributes alloc] init];
    attributes.sourceScope = sourceScope;
    attributes.targetScope = targetScope;
    
    CGFloat actualHeight = CGRectGetHeight(self.collectionView.bounds) + [self.calendar preferredHeaderHeight] + [self.calendar preferredWeekdayHeight];
    CGFloat calendarHeight = CGRectGetHeight(self.calendar.bounds);
    if (actualHeight > calendarHeight) {
        attributes.sourceBounds = CGRectMake(0, 0, CGRectGetWidth(self.calendar.bounds), actualHeight);
    } else {
        attributes.sourceBounds = self.calendar.bounds;
    }
    attributes.sourcePage = self.calendar.currentPage;

    FSCalendarScope normalizedSource = [self normalizedScope:sourceScope];
    FSCalendarScope normalizedTarget = [self normalizedScope:targetScope];
    BOOL involvesWeek = (normalizedSource == FSCalendarScopeWeek || normalizedTarget == FSCalendarScopeWeek);

    if (involvesWeek) {
        NSArray<NSDate *> *candidates = ({
            NSMutableArray *dates = self.calendar.selectedDates.reverseObjectEnumerator.allObjects.mutableCopy;
            if (self.calendar.today) {
                [dates addObject:self.calendar.today];
            }
            if (normalizedTarget == FSCalendarScopeWeek) {
                [dates addObject:self.calendar.currentPage];
            } else {
                [dates addObject:[self.calendar.gregorian dateByAddingUnit:NSCalendarUnitDay value:3 toDate:self.calendar.currentPage options:0]];
            }
            dates.copy;
        });
        NSArray<NSDate *> *visibleCandidates = [candidates filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDate *  _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
            NSIndexPath *indexPath = [self.calendar.calculator indexPathForDate:evaluatedObject scope:normalizedSource];
            NSIndexPath *currentIndex = [self.calendar.calculator indexPathForDate:self.calendar.currentPage scope:normalizedSource];
            return indexPath.section == currentIndex.section;
        }]];
        attributes.focusedDate = visibleCandidates.firstObject ?: self.calendar.currentPage;
        NSIndexPath *monthIndexPath = [self.calendar.calculator indexPathForDate:attributes.focusedDate scope:FSCalendarScopeMonth];
        FSCalendarCoordinate coordinate = [self.calendar.calculator coordinateForIndexPath:monthIndexPath];
        attributes.focusedRow = coordinate.row;
    } else {
        attributes.focusedDate = self.calendar.currentPage;
        attributes.focusedRow = NSNotFound;
    }

    if (normalizedTarget == FSCalendarScopeWeek) {
        attributes.targetPage = [self.calendar.gregorian fs_middleDayOfWeek:attributes.focusedDate];
    } else {
        attributes.targetPage = [self.calendar.gregorian fs_firstDayOfMonth:attributes.focusedDate];
    }
    attributes.targetBounds = [self boundingRectForScope:attributes.targetScope page:attributes.targetPage];
    return attributes;
}

#pragma mark - Private properties

- (FSCalendarScope)representingScope
{
    switch (self.state) {
        case FSCalendarTransitionStateIdle: {
            return self.calendar.scope == FSCalendarScopeMaxHeight ? FSCalendarScopeMonth : self.calendar.scope;
        }
        case FSCalendarTransitionStateChanging:
        case FSCalendarTransitionStateFinishing: {
            return FSCalendarScopeMonth;
        }
    }
}

#pragma mark - Private methods

- (CGRect)boundingRectForScope:(FSCalendarScope)scope page:(NSDate *)page
{
    CGSize contentSize;
    switch (scope) {
        case FSCalendarScopeMonth: {
            contentSize = self.calendar.adjustsBoundingRectWhenChangingMonths ? [self.calendar sizeThatFits:self.calendar.frame.size scope:scope] : self.cachedMonthSize;
            break;
        }
        case FSCalendarScopeWeek: {
            contentSize = [self.calendar sizeThatFits:self.calendar.frame.size scope:scope];
            break;
        }
        case FSCalendarScopeMaxHeight: {
            contentSize = [self.calendar sizeThatFits:self.calendar.frame.size scope:scope];
            break;
        }
    }
    return (CGRect){CGPointZero, contentSize};
}

- (void)boundingRectWillChange:(CGRect)targetBounds animated:(BOOL)animated
{
    BOOL involvesMax = self.transitionAttributes && (self.transitionAttributes.sourceScope == FSCalendarScopeMaxHeight || self.transitionAttributes.targetScope == FSCalendarScopeMaxHeight);
    if (!involvesMax) {
        self.calendar.contentView.fs_height = CGRectGetHeight(targetBounds);
        self.calendar.daysContainer.fs_height = CGRectGetHeight(targetBounds)-self.calendar.preferredHeaderHeight-self.calendar.preferredWeekdayHeight;
        [[self.calendar valueForKey:@"delegateProxy"] calendar:self.calendar boundingRectWillChange:targetBounds animated:animated];
        return;
    }

    self.calendar.contentView.fs_height = CGRectGetHeight(targetBounds);
    CGFloat daysHeight = CGRectGetHeight(targetBounds)-self.calendar.preferredHeaderHeight-self.calendar.preferredWeekdayHeight;
    self.calendar.daysContainer.fs_height = MAX(daysHeight, 0.0f);
    self.collectionView.frame = CGRectMake(0, 0, self.calendar.daysContainer.fs_width, self.calendar.daysContainer.fs_height);
    [self.collectionViewLayout invalidateLayout];
    [[self.calendar valueForKey:@"delegateProxy"] calendar:self.calendar boundingRectWillChange:targetBounds animated:animated];
}

- (void)performTransition:(FSCalendarScope)targetScope fromProgress:(CGFloat)fromProgress toProgress:(CGFloat)toProgress animated:(BOOL)animated
{
    FSCalendarTransitionAttributes *attr = self.transitionAttributes;
    BOOL involvesMax = (attr.sourceScope == FSCalendarScopeMaxHeight || attr.targetScope == FSCalendarScopeMaxHeight);

    [self.calendar willChangeValueForKey:@"scope"];
    [self.calendar fs_setUnsignedIntegerVariable:targetScope forKey:@"_scope"];
    if (targetScope == FSCalendarScopeWeek) {
        [self.calendar fs_setVariable:attr.targetPage forKey:@"_currentPage"];
        if ([self.calendar respondsToSelector:@selector(setCurrentMonth:)]) {
            NSDate *month = [self.calendar.gregorian fs_firstDayOfMonth:attr.focusedDate];
            [self.calendar setCurrentMonth:month];
        }
    }
    [self.calendar didChangeValueForKey:@"scope"];

    if (!involvesMax) {
        if (animated) {
            if (self.calendar.delegate && ([self.calendar.delegate respondsToSelector:@selector(calendar:boundingRectWillChange:animated:)])) {
                [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                    [self performAlphaAnimationWithProgress:toProgress];
                    self.collectionView.fs_top = [self calculateOffsetForProgress:toProgress];
                    [self boundingRectWillChange:attr.targetBounds animated:YES];
                } completion:^(BOOL finished) {
                    [self performTransitionCompletionAnimated:YES];
                }];
            }
        } else {
            [self performTransitionCompletionAnimated:animated];
            [self boundingRectWillChange:attr.targetBounds animated:animated];
        }
        return;
    }

    BOOL needsAlphaAnimation = [self requiresAlphaAnimationForAttributes:attr];
    BOOL needsOffsetAnimation = [self requiresCollectionOffsetForAttributes:attr];

    if (animated) {
        if (self.calendar.delegate && ([self.calendar.delegate respondsToSelector:@selector(calendar:boundingRectWillChange:animated:)])) {
            [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                if (needsAlphaAnimation) {
                    [self performAlphaAnimationWithProgress:toProgress];
                }
                if (needsOffsetAnimation) {
                    self.collectionView.fs_top = [self calculateOffsetForProgress:toProgress];
                } else {
                    self.collectionView.fs_top = 0.0f;
                }
                [self boundingRectWillChange:attr.targetBounds animated:YES];
            } completion:^(BOOL finished) {
                [self performTransitionCompletionAnimated:YES];
            }];
        }
    } else {
        if (needsAlphaAnimation) {
            [self performAlphaAnimationWithProgress:toProgress];
        }
        if (needsOffsetAnimation) {
            self.collectionView.fs_top = [self calculateOffsetForProgress:toProgress];
        } else {
            self.collectionView.fs_top = 0.0f;
        }
        [self boundingRectWillChange:attr.targetBounds animated:animated];
        [self performTransitionCompletionAnimated:animated];
    }
}

- (void)performAlphaAnimationWithProgress:(CGFloat)progress
{
    if (self.transitionAttributes.focusedRow == NSNotFound) {
        return;
    }
    CGFloat opacity = self.transitionAttributes.targetScope == FSCalendarScopeWeek ? MAX((1-progress*1.1f), 0.0f) : progress;
    NSArray<FSCalendarCell *> *surroundingCells = [self.calendar.visibleCells filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(FSCalendarCell *  _Nullable cell, NSDictionary<NSString *,id> * _Nullable bindings) {
        if (!CGRectContainsPoint(self.collectionView.bounds, cell.center)) {
            return NO;
        }
        NSIndexPath *indexPath = [self.collectionView indexPathForCell:cell];
        NSInteger row = [self.calendar.calculator coordinateForIndexPath:indexPath].row;
        return row != self.transitionAttributes.focusedRow;
    }]];
    [surroundingCells setValue:@(opacity) forKey:@"alpha"];
}

- (void)performPathAnimationWithProgress:(CGFloat)progress
{
    CGFloat targetHeight = CGRectGetHeight(self.transitionAttributes.targetBounds);
    CGFloat sourceHeight = CGRectGetHeight(self.transitionAttributes.sourceBounds);
    CGFloat currentHeight = sourceHeight - (sourceHeight-targetHeight)*progress;
    CGRect currentBounds = CGRectMake(0, 0, CGRectGetWidth(self.transitionAttributes.targetBounds), currentHeight);
    if ([self requiresCollectionOffsetForAttributes:self.transitionAttributes]) {
        self.collectionView.fs_top = [self calculateOffsetForProgress:progress];
    } else {
        self.collectionView.fs_top = 0.0f;
    }
    [self boundingRectWillChange:currentBounds animated:NO];
    if (self.transitionAttributes.targetScope == FSCalendarScopeMonth) {
        if (self.transitionAttributes.sourceScope == FSCalendarScopeWeek) {
            self.calendar.contentView.fs_height = targetHeight;
        }
    } else if (self.transitionAttributes.targetScope == FSCalendarScopeMaxHeight) {
        self.calendar.contentView.fs_height = targetHeight;
    }
}

- (CGFloat)calculateOffsetForProgress:(CGFloat)progress
{
    if (self.transitionAttributes.focusedRow == NSNotFound) {
        return 0.0f;
    }
    NSIndexPath *indexPath = [self.calendar.calculator indexPathForDate:self.transitionAttributes.focusedDate scope:FSCalendarScopeMonth];
    CGRect frame = [self.collectionViewLayout layoutAttributesForItemAtIndexPath:indexPath].frame;
    CGFloat ratio;
    if (self.transitionAttributes.targetScope == FSCalendarScopeWeek) {
        ratio = progress;
    } else if (self.transitionAttributes.sourceScope == FSCalendarScopeWeek) {
        ratio = 1 - progress;
    } else {
        return 0.0f;
    }
    CGFloat offset = (-frame.origin.y + self.collectionViewLayout.sectionInsets.top) * ratio;
    return offset;
}

- (void)prepareWeekToMonthTransition
{
    [self.calendar fs_setVariable:self.transitionAttributes.targetPage forKey:@"_currentPage"];
    self.calendar.contentView.fs_height = CGRectGetHeight(self.transitionAttributes.targetBounds);
    self.collectionViewLayout.scrollDirection = (UICollectionViewScrollDirection)self.calendar.scrollDirection;
    self.calendar.calendarHeaderView.scrollDirection = self.collectionViewLayout.scrollDirection;
    self.calendar.needsAdjustingViewFrame = YES;
    
    [CATransaction begin];
    [CATransaction setDisableActions:NO];
    [self.collectionView reloadData];
    [self.calendar.calendarHeaderView reloadData];
    [self.calendar layoutIfNeeded];
    [CATransaction commit];
    
    self.collectionView.fs_top = [self calculateOffsetForProgress:0];
}

- (FSCalendarScope)normalizedScope:(FSCalendarScope)scope
{
    return scope == FSCalendarScopeMaxHeight ? FSCalendarScopeMonth : scope;
}

- (BOOL)requiresAlphaAnimationForAttributes:(FSCalendarTransitionAttributes *)attributes
{
    return attributes.focusedRow != NSNotFound;
}

- (BOOL)requiresCollectionOffsetForAttributes:(FSCalendarTransitionAttributes *)attributes
{
    FSCalendarScope normalizedSource = [self normalizedScope:attributes.sourceScope];
    FSCalendarScope normalizedTarget = [self normalizedScope:attributes.targetScope];
    return normalizedSource == FSCalendarScopeWeek || normalizedTarget == FSCalendarScopeWeek;
}

- (void)performMaxHeightExpansionWithDuration:(CGFloat)duration
{
    if (self.state != FSCalendarTransitionStateIdle) {
        return;
    }

    // 当前必须在 maxHeight 模式
    if (self.calendar.scope != FSCalendarScopeMaxHeight) {
        return;
    }

    // 计算当前bounds和目标bounds（重新设置maxHeight后的bounds）
    CGRect currentBounds = self.calendar.bounds;
    CGFloat actualHeight = CGRectGetHeight(self.collectionView.bounds) + [self.calendar preferredHeaderHeight] + [self.calendar preferredWeekdayHeight];
    CGFloat calendarHeight = CGRectGetHeight(self.calendar.bounds);
    if (actualHeight > calendarHeight) {
        currentBounds = CGRectMake(0, 0, CGRectGetWidth(self.calendar.bounds), actualHeight);
    }
        
        
    CGRect targetBounds = [self boundingRectForScope:FSCalendarScopeMaxHeight page:self.calendar.currentPage];

    // 如果高度变化太小，不执行动画
    CGFloat deltaHeight = CGRectGetHeight(targetBounds) - CGRectGetHeight(currentBounds);
    if (fabs(deltaHeight) < 1.0) {
        return;
    }

    // 创建 transition attributes，模拟从当前高度到目标高度的过渡
    FSCalendarTransitionAttributes *attr = [[FSCalendarTransitionAttributes alloc] init];
    attr.sourceBounds = currentBounds;
    attr.targetBounds = targetBounds;
    attr.sourceScope = FSCalendarScopeMaxHeight;
    attr.targetScope = FSCalendarScopeMaxHeight;
    attr.sourcePage = self.calendar.currentPage;
    attr.targetPage = self.calendar.currentPage;
    attr.focusedRow = NSNotFound;  // maxHeight模式不需要行聚焦

    self.transitionAttributes = attr;
    self.state = FSCalendarTransitionStateChanging;

    // 使用 UIView 动画，模拟 progress 从 0 到 1 的过程
    // 通过 CADisplayLink 实现类似 scopeTransitionDidUpdate 的效果
    // 延迟 100 毫秒（0.1 秒）开始动画
    __block CFTimeInterval startTime = CACurrentMediaTime() + 0.2;
    __weak typeof(self) weakSelf = self;

    CADisplayLink *displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(maxHeightExpansionTick:)];
    displayLink.preferredFramesPerSecond = 60;
    self.displayLink = displayLink;
    [displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

    // 存储动画参数
    objc_setAssociatedObject(self, "animationStartTime", @(startTime), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, "animationDuration", @(duration), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)maxHeightExpansionTick:(CADisplayLink *)displayLink
{
    CFTimeInterval startTime = [objc_getAssociatedObject(self, "animationStartTime") doubleValue];
    CGFloat duration = [objc_getAssociatedObject(self, "animationDuration") doubleValue];

    CFTimeInterval elapsed = CACurrentMediaTime() - startTime;
    CGFloat progress = MIN(elapsed / duration, 1.0);

    // 使用 ease-out 缓动
    CGFloat easedProgress = 1.0 - pow(1.0 - progress, 2.0);

    // 调用现有的 performPathAnimationWithProgress 方法
    [self performPathAnimationWithProgress:easedProgress];


    // 动画完成
    if (progress >= 1.0) {
        [self.displayLink invalidate];
        self.displayLink = nil;
        self.transitionAttributes = nil;
        self.state = FSCalendarTransitionStateIdle;

        // 确保最终布局正确
        self.calendar.needsAdjustingViewFrame = YES;
        [self.calendar setNeedsLayout];

    }
}

@end

@implementation FSCalendarTransitionAttributes

- (instancetype)init
{
    self = [super init];
    if (self) {
        _focusedRow = NSNotFound;
    }
    return self;
}

- (void)revert
{
    CGRect tempRect = self.sourceBounds;
    self.sourceBounds = self.targetBounds;
    self.targetBounds = tempRect;

    NSDate *tempDate = self.sourcePage;
    self.sourcePage = self.targetPage;
    self.targetPage = tempDate;
    FSCalendarScope tempScope = self.sourceScope;
    self.sourceScope = self.targetScope;
    self.targetScope = tempScope;
}
    
@end
