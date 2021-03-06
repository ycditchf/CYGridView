//
//  CYCollectionView.m
//  CYTagView
//
//  Created by SimonChen on 17/3/28.
//  Copyright © 2017年 rainbow. All rights reserved.
//

#import "CYCollectionView.h"
#import "CYCollectionCell.h"
#import "UIView+CYCollectionView.h"

#define kVisibleCellsKey @"CELLS_SECTION"

@interface CYCollectionView () <UIGestureRecognizerDelegate>

/**
 key: reuseIdentifier
 value: 装有可重复利用的cell（NSMutableSet）
 */
@property (nonatomic, strong) NSMutableDictionary *reuseCells;
@property (nonatomic, strong) NSMutableDictionary *allVisibleCells; //可见视图 TODO:目前包括不可见视图
@property (nonatomic, strong) NSMutableArray *allSupplementViews; //页眉、页脚

/**
 key： 对应 section key
 value: 对应 section cell的容器视图 (UIView)
 */
@property (nonatomic, strong) NSMutableDictionary *containers;
@property (nonatomic, strong) UIView *containerView;

@property (nonatomic, strong) NSMutableDictionary *itemFrameCache;
@property (nonatomic, assign) BOOL isPickUpCell;
@property (nonatomic, assign) BOOL isItemMoving;
@property (nonatomic, strong) CYCollectionCell *pickUpCell;
@property (nonatomic, assign) NSIndexPath *pickUpIndexPath;



//@property (nonatomic, strong) UIScrollView *scrollView;
@end

@implementation CYCollectionView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self configData];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self configData];
    }
    return self;
}

- (void)configData
{
    _reuseCells = @{}.mutableCopy;
    _allVisibleCells = @{}.mutableCopy;
    _allSupplementViews = @[].mutableCopy;
    _containers = @{}.mutableCopy;
    _itemFrameCache = @{}.mutableCopy;

    self.backgroundColor = [UIColor whiteColor];

    self.containerView = [[UIView alloc] initWithFrame:self.bounds];
    [self addSubview:self.containerView];
}

- (void)layoutSubviews
{
    [super layoutSubviews];

}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
}
*/

- (void)setup
{
    [self updateContentSize];
    [self setupSubViews];
}

- (void)updateContentSize
{
    //固定行高
    CGFloat contentHeight = [self heightOfContent];
    CGFloat contentWidth = self.bounds.size.width;

    CGSize contentSize = CGSizeMake(contentWidth, contentHeight);
    self.contentSize = contentSize;

    CGRect frame = self.containerView.frame;
    frame.size.height = self.contentSize.height;
    self.containerView.frame = frame;
}

- (void)setupSubViews
{
    NSInteger section = [self numberOfSection];

    for (int i=0; i<section; i++) {

        CGFloat offsetY = 0;

        UIView *containerView = [self itemsContainerAtSection:i];
        containerView.frame = [self frameForContainerAtSection:i];
        [self.containerView addSubview:containerView];

        //Add HeaderView
        UIView *headView = [self headerViewForSection:i];

        if (headView) {

            CGRect frame = headView.frame;
            frame.origin.y = offsetY;
            headView.frame = frame;
            [containerView addSubview:headView];
            offsetY += frame.size.height;

            [self.allSupplementViews addObject:headView];
        }

        //Add Items
        [self setupItemsOfSection:i];
        offsetY += [self heightOfSectionContent:i];

        //Add FooterView
        UIView *footerView = [self footerViewForSection:i];

        if (footerView) {
            CGRect frame = footerView.frame;
            frame.origin.y = offsetY;
            footerView.frame = frame;
            [containerView addSubview:footerView];

            offsetY += frame.size.height;

            [self.allSupplementViews addObject:headView];
        }
    }
}

- (void)setupItemsOfSection:(NSInteger)section
{
    NSInteger rowCount = [self numberOfRowAtSection:section];

    for (int i=0; i<rowCount; i++) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i inSection:section];
        [self addCollectionCellAtIndexPath:indexPath];
    }
}

- (void)addGridCell:(CYCollectionCell *)cell atIndexPath:(NSIndexPath *)indexPath
{
    cell.indexPath = indexPath;
    cell.frame = [self frameForItemAtIndexPath:indexPath];
    [self addVisibleCell:cell];
    UIView *containerView = [self itemsContainerAtSection:indexPath.section];
    [containerView addSubview:cell];
}

- (void)addCollectionCellAtIndexPath:(NSIndexPath *)indexPath
{
    CYCollectionCell *itemView = [self dequeueReusableCellAtIndexPath:indexPath];
    [self addGridCell:itemView atIndexPath:indexPath];
}

- (CYCollectionCell *)removeItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *key = [NSString stringWithFormat:@"%@%zd", kVisibleCellsKey, indexPath.section];

    NSMutableArray *visibleCells = self.allVisibleCells[key];
    __block CYCollectionCell *removeCell = nil;
    [visibleCells enumerateObjectsUsingBlock:^(CYCollectionCell *obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([obj.indexPath isEqual:indexPath]) {
            removeCell = obj;
            *stop = YES;
        }
    }];
    [visibleCells removeObject:removeCell];
    [self clearItemFrameCacheFromIndexPath:removeCell.indexPath];
    return removeCell;
}

- (void)addTapGesture:(CYCollectionCell *)cell
{
    if (!cell.collectionView_tapGesture) {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTap:)];
        [cell addGestureRecognizer:tap];
        cell.collectionView_tapGesture = tap;
    }
}

- (void)onTap:(UIGestureRecognizer *)gesture
{
    CYCollectionCell *cell = (CYCollectionCell *)gesture.view;
    if ([self.gridDelegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) {
        [self.gridDelegate collectionView:self didSelectItemAtIndexPath:cell.indexPath];
    }
}

- (void)addPanGesture:(CYCollectionCell *)cell
{
    if (!cell.collectionView_panGesture) {
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanGesture:)];
        pan.delegate = self;
        [cell addGestureRecognizer:pan];
        cell.collectionView_panGesture = pan;
    }
}

- (void)onPanGesture:(UIGestureRecognizer *)gesture
{
    CYCollectionCell *cell = (CYCollectionCell *)gesture.view;
    UIView *containerView = [self itemsContainerAtSection:cell.indexPath.section];

    if (gesture.state == UIGestureRecognizerStateBegan) {

        self.isPickUpCell = YES;
        [containerView bringSubviewToFront:cell];
        self.pickUpCell = cell;
        self.pickUpIndexPath = cell.indexPath;

    }else if (gesture.state == UIGestureRecognizerStateChanged){
        //TODO:目前只考虑在同一Section中移动
        if (self.isPickUpCell) {
            CGPoint point = [gesture locationInView:containerView];
            CGFloat areaTop = [self heightOfSectionHeader:cell.indexPath.section];
            CGFloat areaHeight = [self heightOfSection:cell.indexPath.section];

            CGFloat sensitiveLimit = 30;
            if (point.y - cell.bounds.size.height/2 > (areaTop-sensitiveLimit) &&
                point.y + cell.bounds.size.height/2 < (areaHeight+sensitiveLimit)) {
                //TODO:优化
                cell.center = [gesture locationInView:containerView];
                [self moveOtherItemsIfNeeded];
            }else{
                gesture.enabled = NO;
                [self endPanGesture:gesture];
                gesture.enabled = YES;
            }
        }
    }else{
        [self endPanGesture:gesture];
    }
}

- (void)endPanGesture:(UIGestureRecognizer *)gesture
{
    [UIView animateWithDuration:0.3 animations:^{
        self.pickUpCell.frame = [self frameForItemAtIndexPath:self.pickUpIndexPath];
    } completion:^(BOOL finished) {
        self.isPickUpCell = NO;
        self.pickUpCell = nil;
    }];
}

- (void)moveOtherItemsIfNeeded
{
    if (self.isItemMoving) {
        return;
    }

    //TODO: 先考虑在一个 section 移动
    NSInteger section = self.pickUpCell.indexPath.section;
    //计算是否还在当前的 indexPath 上
    CGRect frame = [self frameForItemAtIndexPath:self.pickUpIndexPath];
//    CGRect realFrame = self.pickUpCell.frame;
    CGPoint realCenter = self.pickUpCell.center;

    CGFloat rowHeight = frame.size.height + [self lineSpacingForSectionAtIndex:section];

    CGFloat headerHeight = [self heightOfSectionHeader:section];
    //先判断上下
    //之前在第几行
//    NSInteger preCellRow = CGRectGetMinY(CGRectOffset(frame, 0, headerHeight))/rowHeight;

    //目前在第几行
    NSInteger realCellRow = (realCenter.y - headerHeight)/rowHeight;
    NSLog(@"realCellRow:%zd",realCellRow);

    //优化：先比自己的左右、然后按最后一个倒序比较
    NSInteger toIndex = self.pickUpIndexPath.row;

    NSInteger beginIndex = -1;
    if ([self.gridDelegate respondsToSelector:@selector(collectionViewBeginDragIndex:atSection:)]) {
        beginIndex = [self.gridDelegate collectionViewBeginDragIndex:self atSection:section];
    }

    NSLog(@"beginIndex+1:%zd",beginIndex+1);
    for (NSInteger i=beginIndex+1; i<[self numberOfRowAtSection:section]; i++) {

        if (toIndex == i) {
            continue;
        }

        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i inSection:section];
        CGRect frame = [self frameForItemAtIndexPath:indexPath];
        CGPoint center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
        NSInteger row = (center.y- headerHeight)/rowHeight;
        NSLog(@"row:%zd",row);

        //比较最后一个
        if (i == [self numberOfRowAtSection:section]-1) {
            NSLog(@"i:%zd center:%@ last one row:%zd",i, NSStringFromCGPoint(center),row);
            if (realCellRow >= row && realCenter.x > center.x) {
                toIndex = [self numberOfRowAtSection:section]-1;
                break;
            }
        }

        //同一行
        if (row == realCellRow) {
            if (center.x > realCenter.x) {
                //需要区分是往前拖动还是往后
                if (self.pickUpIndexPath.row < i) {
                    toIndex = i-1;
                }else{
                    toIndex = i;
                }
                break;
            }
        }else if(row > realCellRow){
            if (self.pickUpIndexPath.row < i) {
                toIndex = i-1;
            }else{
                toIndex = i;
            }
            break;
        }

    }


    if (self.pickUpIndexPath.row != toIndex) {
        NSLog(@"oring:%zd to index:%zd",self.pickUpIndexPath.row, toIndex);

        NSInteger beginIndex = MIN(self.pickUpIndexPath.row, toIndex);

        //移动其他的 item 到合适位置
        NSString *key = [NSString stringWithFormat:@"%@%zd", kVisibleCellsKey, self.pickUpCell.indexPath.section];
        NSMutableArray *visibleCells = self.allVisibleCells[key];

        NSMutableArray *willUpdateCell = @[].mutableCopy;
        [visibleCells enumerateObjectsUsingBlock:^(CYCollectionCell *obj, NSUInteger idx, BOOL * _Nonnull stop) {

            if (obj != self.pickUpCell) {
                NSInteger row = obj.indexPath.row;
                if (self.pickUpIndexPath.row < toIndex) { //往后拖
                    if (row > self.pickUpIndexPath.row && row <= toIndex) {
                        obj.indexPath = [NSIndexPath indexPathForRow:row-1 inSection:section];
                    }

                }else{//往前拖
                    if (row >= toIndex && row < self.pickUpIndexPath.row) {
                        obj.indexPath = [NSIndexPath indexPathForRow:row+1 inSection:section];
                    }
                }

                //由于后续位置都不能确定, 所以之后的item都需要更新frame

                if (obj.indexPath.row >= beginIndex) {
                    [willUpdateCell addObject:obj];
                }
            }
        }];

        NSLog(@"willUpdateCell:%@",willUpdateCell);
        //告诉代理顺序已经换了
        SEL selector = @selector(collectionView:moveItemAtIndexPath:toIndexPath:);
        NSAssert([self.gridDelegate respondsToSelector:selector], NSStringFromSelector(selector));
        NSIndexPath *toIndexPath = [NSIndexPath indexPathForRow:toIndex inSection:section];
        [self.gridDelegate collectionView:self moveItemAtIndexPath:self.pickUpIndexPath toIndexPath:toIndexPath];

        [self clearItemFrameCacheFromIndexPath:[NSIndexPath indexPathForRow:beginIndex inSection:section]];
        self.pickUpIndexPath = toIndexPath;
        self.pickUpCell.indexPath = self.pickUpIndexPath;

        self.isItemMoving = YES;
        [self updateItemsFrame:willUpdateCell completion:^{
            self.isItemMoving = NO;
        }];
        [self updateItemsContainerFrame];
        [self updateContentSize];

    }
}

#pragma mark - UIGestureDelegate
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    if (![gestureRecognizer.view isKindOfClass:[CYCollectionCell class]]) {
        return YES;
    }

//    if ([gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]]) {
//        return YES;
//    }

    if ([gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]] ) {
        //        if (self.isEdit) {
        CYCollectionCell *cell = (CYCollectionCell *)gestureRecognizer.view;
        if (![cell isKindOfClass:[CYCollectionCell class]]) {
            return NO;
        }
        if ([self.gridDelegate respondsToSelector:@selector(collectionViewShouldReorder:atIndexPath:)]) {
            return [self.gridDelegate collectionViewShouldReorder:self atIndexPath:cell.indexPath];
        }
        //            NSInteger beginIndex = -1;
        //            if ([self.gridDelegate respondsToSelector:@selector(collectionViewBeginDragIndex:atSection:)]) {
        //                beginIndex = [self.gridDelegate collectionViewBeginDragIndex:self atSection:cell.indexPath.section];
        //            }
        //            if (cell.indexPath.row <= beginIndex) {
        //                return NO;
        //            }
        //        }
        //        return self.isEdit;
        return NO;
    }
    
    
    return YES;
}

#pragma mark - Helper
- (UIView *)itemsContainerAtSection:(NSInteger)section
{
    NSString *key = [NSString stringWithFormat:@"%zd",section];
    UIView *view = self.containers[key];
    if (!view) {
        view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.containerView.bounds.size.width, 100)];
        view.autoresizesSubviews = NO;
        self.containers[key] = view;
    }
    return view;
}

- (void)removeAllItemsView
{
    for (NSString *key in self.containers.allKeys) {
        UIView *view = self.containers[key];

        [view.subviews enumerateObjectsUsingBlock:^(__kindof UIView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if ([obj isKindOfClass:[CYCollectionCell class]]) {
                CYCollectionCell *cell = (CYCollectionCell *)obj;
                [self removeCell:cell];
            }
        }];
        [view.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

    }
}


//TODO:优化
#pragma mark - CYCollectionCell Frame Cache Method
- (CGRect)itemCacheFrameAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *sectionkey = [NSString stringWithFormat:@"secion_%zd",indexPath.section];
    NSMutableDictionary *rowInfo = self.itemFrameCache[sectionkey];
    if (!rowInfo) {
        return CGRectNull;
    }

    NSString *rowKey = [NSString stringWithFormat:@"%zd",indexPath.row];
    NSValue *value = rowInfo[rowKey];
    if (value) {
        return [value CGRectValue];
    }
    return CGRectNull;
}

- (void)saveItemFrame:(CGRect)frame atIndexPath:(NSIndexPath *)indexPath
{
    NSString *sectionkey = [NSString stringWithFormat:@"secion_%zd",indexPath.section];
    NSMutableDictionary *rowInfo = self.itemFrameCache[sectionkey];

    if (!rowInfo) {
        rowInfo = @{}.mutableCopy;
        self.itemFrameCache[sectionkey] = rowInfo;
    }

    NSString *rowKey = [NSString stringWithFormat:@"%zd",indexPath.row];
    rowInfo[rowKey] = [NSValue valueWithCGRect:frame];
}

- (void)clearItemFrameCacheFromIndexPath:(NSIndexPath *)indexPath
{
    NSString *sectionkey = [NSString stringWithFormat:@"secion_%zd",indexPath.section];
    NSMutableDictionary *rowInfo = self.itemFrameCache[sectionkey];

    NSMutableArray *rowkeys = @[].mutableCopy;
    for (NSString *rowKey in rowInfo.allKeys) {
        NSInteger row = [rowKey integerValue];
        if (row >= indexPath.row) {
            [rowkeys addObject:rowKey];
        }
    }

    [rowInfo removeObjectsForKeys:rowkeys];
}

- (void)clearAllItemCache
{
    [self.itemFrameCache removeAllObjects];
    [self.allVisibleCells removeAllObjects];
}
#pragma mark - Helper Frame Method
- (CGFloat)heightOfContent
{
    NSInteger section = [self numberOfSection];
    CGFloat height = 0;
    for (int i=0; i<section; i++) {
        height += [self heightOfSection:i];
    }
    return height;
}

- (CGFloat)heightOfSection:(NSInteger)section
{
    CGFloat height = 0;
    height += [self heightOfSectionHeader:section];
    height += [self heightOfSectionContent:section];
    height += [self heightOfSectionFooter:section];
    return height;
}

- (CGFloat)contentWidthOfSection:(NSInteger)section
{
    UIEdgeInsets insets = [self insetForSectionAtIndex:section];
    CGFloat contentWidth = self.containerView.bounds.size.width - insets.left - insets.right;

    return contentWidth;
}

- (CGFloat)heightOfSectionHeader:(NSInteger)section
{
    CGFloat height = 0;
    UIView *view = nil;
    if ([self.gridDelegate respondsToSelector:@selector(collectionView:headerViewForSection:)]) {
        view = [self.gridDelegate collectionView:self headerViewForSection:section];
        height = view.bounds.size.height;
    }
    return height;
}

- (CGFloat)heightOfSectionFoot:(NSInteger)section
{
    CGFloat height = 0;
    //TODO
    return height;
}

//对应 section 的内容高度
//TODO: 优化
- (CGFloat)heightOfSectionContent:(NSInteger)section
{
    NSInteger rowCount = [self numberOfRowAtSection:section];
    UIEdgeInsets insets = [self insetForSectionAtIndex:section];

    CGFloat contentWidth = [self contentWidthOfSection:section];

    CGFloat minimumInteritemSpacing = [self interitemSpacingForSectionAtIndex:section];;
    CGFloat minimumLineSpacing = [self lineSpacingForSectionAtIndex:section];

    CGSize itemSize = CGSizeMake(80, 80);

    CGFloat offsetX = insets.left;
    CGFloat offsetY = insets.top;

    for (int i=0; i<rowCount; i++) {

        if (i == 0) {
            offsetX = insets.left;
        }else{
            offsetX += minimumInteritemSpacing;
        }

        itemSize = [self sizeForItemAtRow:i section:section];

        //第一个就过长的不换行
        if (offsetX + itemSize.width > (contentWidth+insets.left) && fabs(offsetX - insets.left) > 0.01) { //换行
            offsetX = insets.left;
            offsetY += minimumLineSpacing;
            offsetY += itemSize.height;
        }
        offsetX += itemSize.width;
    }
    CGFloat height = offsetY + itemSize.height + insets.bottom;
    return height;
}

- (CGFloat)heightOfSectionFooter:(NSInteger)section
{
    //TODO:
    return 0;
}
#pragma mark - CYCollectionCell Method
- (void)addVisibleCell:(CYCollectionCell *)cell
{
    NSIndexPath *indexPath = cell.indexPath;
    NSString *key = [NSString stringWithFormat:@"%@%zd", kVisibleCellsKey, indexPath.section];

    NSMutableArray *visibleCells = self.allVisibleCells[key];
    if (!visibleCells) {
        visibleCells = @[].mutableCopy;
        self.allVisibleCells[key] = visibleCells;
    }

    [visibleCells addObject:cell];
}

- (void)removeCell:(CYCollectionCell *)cell
{
    [self addReuseCell:cell];

    NSIndexPath *indexPath = cell.indexPath;
    NSString *key = [NSString stringWithFormat:@"%@%zd", kVisibleCellsKey, indexPath.section];

    NSMutableArray *visibleCells = self.allVisibleCells[key];
    [visibleCells removeObject:cell];
}

- (CYCollectionCell *)dequeueReusableCellAtIndexPath:(NSIndexPath *)indexPath
{
    CYCollectionCell *cell = [self cellForRowAtRow:indexPath.row section:indexPath.section];
    if (cell) {
        [self addTapGesture:cell];
        [self addPanGesture:cell];
    }
    cell.indexPath = indexPath;
    return  cell;
}

- (CYCollectionCell *)dequeueReusableCellWithIdentifier:(NSString *)identifier
{
    if (!identifier) {
        return nil;
    }

    CYCollectionCell *cell = nil;
    NSMutableSet *aSet = self.reuseCells[identifier];
    if (aSet) {
        cell = aSet.anyObject;
        if (cell) {
            [aSet removeObject:cell];
        }
    }
    return cell;
}

- (void)addReuseCell:(CYCollectionCell *)cell
{
    if (!cell.reuseIdentifier) {
        return;
    }

    NSMutableSet *aSet = self.reuseCells[cell.reuseIdentifier];
    if (!aSet) {
        aSet = [NSMutableSet new];
        self.reuseCells[cell.reuseIdentifier] = aSet;
    }
    [aSet addObject:cell];
}

//TODO：资源重复利用的情况下可能不存
- (CYCollectionCell *)cellForItemIndexPath:(NSIndexPath *)indexPath
{
    __block CYCollectionCell *cell = nil;
    NSString *key = [NSString stringWithFormat:@"%@%zd", kVisibleCellsKey, indexPath.section];
    NSMutableArray *visibleCells = self.allVisibleCells[key];

    [visibleCells enumerateObjectsUsingBlock:^(CYCollectionCell *obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([obj.indexPath isEqual:indexPath]) {
            cell = obj;
            *stop = YES;
        }
    }];

    return cell;
}

- (CGRect)frameForContainerAtSection:(NSInteger)section
{
    CGFloat top = 0;
    for (int i=0; i<section; i++) {
        top += [self heightOfSection:i];
    }

    CGFloat height = [self heightOfSection:section];
    CGRect frame = CGRectMake(0, top, self.containerView.bounds.size.width, height);
//    NSLog(@"section %zd, frame:%@", section, NSStringFromCGRect(frame));
    return frame;
}

//- (CGRect)frameForItemHeaderAtSection:(NSInteger)section
//{
//    __block UIView *headerView = nil;
//    [self.allSupplementViews enumerateObjectsUsingBlock:^(UIView *obj, NSUInteger idx, BOOL * _Nonnull stop) {
//        if (obj.collectionViewSectionIndex == section) {
//            headerView = obj;
//            *stop = YES;
//        }
//    }];
//
//    if (!headerView) {
//        headerView = [self headerViewForSection:section];
//    }
//
////    CGFloat top = 0;
////    for (int i=0; i<section; i++) {
////        top += [self heightOfSection:i];
////    }
//
//    CGRect frame = headerView.frame;
//    frame.origin.y = 0;
//    return frame;
//}

- (CGRect)frameForItemFooterAtIndexPath:(NSIndexPath *)indexPath
{
    //TODO:
    return CGRectZero;
}

- (CGRect)frameForItemAtIndexPath:(NSIndexPath *)indexPath
{
    CGFloat frameTop = 0;

    CGRect cacheFrame = [self itemCacheFrameAtIndexPath:indexPath];
    if (!CGRectEqualToRect(cacheFrame, CGRectNull)) {
        return cacheFrame;
    }

    //add headerview height
    frameTop += [self heightOfSectionHeader:indexPath.section];

    UIEdgeInsets insets = [self insetForSectionAtIndex:indexPath.section];
    CGSize itemSize = [self sizeForItemAtRow:indexPath.row section:indexPath.section];

    CGRect frame = CGRectMake(0, 0, itemSize.width, itemSize.height);

    frameTop += insets.top;

    if (indexPath.row == 0) {
        frame.origin.x = insets.left;
        frame.origin.y = frameTop;
        [self saveItemFrame:frame atIndexPath:indexPath];
        return frame;
    }

    CGFloat minimumInteritemSpacing = [self interitemSpacingForSectionAtIndex:indexPath.section];
    CGFloat minimumLineSpacing = [self lineSpacingForSectionAtIndex:indexPath.section];

    NSIndexPath *lastOneIndexPath = [NSIndexPath indexPathForRow:indexPath.row-1 inSection:indexPath.section];

    CGRect lastOneCellFrame = [self frameForItemAtIndexPath:lastOneIndexPath];

    CGFloat contentWidth = [self contentWidthOfSection:indexPath.section];
    CGFloat itemOffsetX = lastOneCellFrame.origin.x + lastOneCellFrame.size.width;
    CGFloat itemOffsetY = lastOneCellFrame.origin.y;
    itemOffsetX += minimumInteritemSpacing;

    if (itemOffsetX + itemSize.width > (contentWidth+insets.left) && fabs(itemOffsetX - insets.left) > 0.01) { //换行
        itemOffsetX = insets.left;
        itemOffsetY += minimumLineSpacing;
        itemOffsetY += itemSize.height;
    }

    frame.origin.x = itemOffsetX;
    frame.origin.y = itemOffsetY;

    [self saveItemFrame:frame atIndexPath:indexPath];
    return frame;

}

#pragma mark - Wrap gridDelegate Method
- (NSInteger)numberOfSection
{
    NSInteger section = 1;
    if ([self.gridDelegate respondsToSelector:@selector(numberOfSectionInCollectionView:)]) {
        section = [self.gridDelegate numberOfSectionInCollectionView:self];
    }
    return section;
}

- (NSInteger)numberOfRowAtSection:(NSInteger)section
{
    NSInteger rowCount = 0;
    if ([self.gridDelegate respondsToSelector:@selector(collectionView:numberOfRowsInSection:)]) {
        rowCount = [self.gridDelegate collectionView:self numberOfRowsInSection:section];
    }
    return rowCount;
}

- (CGSize)sizeForItemAtRow:(NSInteger)row section:(NSInteger)section
{
    CGSize itemSize = CGSizeMake(80, 80);
    if ([self.gridDelegate respondsToSelector:@selector(collectionView:sizeForItemAtIndexPath:)]) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:section];
        itemSize = [self.gridDelegate collectionView:self sizeForItemAtIndexPath:indexPath];
    }
    return itemSize;
}

- (CYCollectionCell *)cellForRowAtRow:(NSInteger)row section:(NSInteger)section
{
    CYCollectionCell *cell = nil;
    if ([self.gridDelegate respondsToSelector:@selector(collectionView:cellForRowAtIndexPath:)]) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:section];
        cell = [self.gridDelegate collectionView:self cellForRowAtIndexPath:indexPath];
        cell.indexPath = indexPath;
    }
    return cell;
}

- (UIView *)headerViewForSection:(NSInteger)section
{
    UIView *view = nil;
    if ([self.gridDelegate respondsToSelector:@selector(collectionView:headerViewForSection:)]) {
        view = [self.gridDelegate collectionView:self headerViewForSection:section];
        view.collectionViewSectionIndex = section;
    }
    return view;
}

- (UIView *)footerViewForSection:(NSInteger)section
{
    UIView *view = nil;
    if ([self.gridDelegate respondsToSelector:@selector(collectionView:footerViewForSection:)]) {
        view = [self.gridDelegate collectionView:self footerViewForSection:section];
        view.collectionViewSectionIndex = section;
    }
    return view;
}

- (CGFloat)interitemSpacingForSectionAtIndex:(NSInteger)section
{
    if ([self.gridDelegate respondsToSelector:@selector(collectionView:interitemSpacingForSectionAtIndex:)]) {
        return [self.gridDelegate collectionView:self interitemSpacingForSectionAtIndex:section];
    }
    return 0;
}

- (CGFloat)lineSpacingForSectionAtIndex:(NSInteger)section
{
    if ([self.gridDelegate respondsToSelector:@selector(collectionView:lineSpacingForSectionAtIndex:)]) {
        return [self.gridDelegate collectionView:self lineSpacingForSectionAtIndex:section];
    }
    return 0;
}

- (UIEdgeInsets)insetForSectionAtIndex:(NSInteger)section
{
    if ([self.gridDelegate respondsToSelector:@selector(collectionView:insetForSectionAtIndex:)]) {
        return [self.gridDelegate collectionView:self insetForSectionAtIndex:section];
    }
    return UIEdgeInsetsZero;
}

#pragma mark - Public Method
- (void)reloadData
{
    [self removeAllItemsView];
    [self.containerView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    [self clearAllItemCache];
    [self setup];
}

- (void)insertItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths
{
    NSMutableArray *willUpdateItems = @[].mutableCopy;

    for (NSIndexPath *indexPath in indexPaths) {

        //插入之前要改变在这个位置之后cell的indexPath
        NSString *key = [NSString stringWithFormat:@"%@%zd", kVisibleCellsKey, indexPath.section];
        NSMutableArray *visibleCells = self.allVisibleCells[key];

        [visibleCells enumerateObjectsUsingBlock:^(CYCollectionCell *obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if (obj.indexPath.section == indexPath.section &&
                obj.indexPath.row >= indexPath.row) {
                obj.indexPath = [NSIndexPath indexPathForRow:obj.indexPath.row+1 inSection:obj.indexPath.section];
                [willUpdateItems addObject:obj];
            }
        }];

        [self addCollectionCellAtIndexPath:indexPath];
    }

    for (CYCollectionCell *cell in willUpdateItems) {
        [self clearItemFrameCacheFromIndexPath:cell.indexPath];
    }


    [self updateItemsFrame:willUpdateItems completion:^{
    }];
    [self updateItemsContainerFrame];
    [self updateContentSize];
}
//
////每个section 最小值
//- (NSArray *)startIndexPath:(NSArray *)indexPaths
//{
//    NSMutableArray *temp = @[].mutableCopy;
//    [indexPaths enumerateObjectsUsingBlock:^(NSIndexPath *obj, NSUInteger idx, BOOL * _Nonnull stop) {
//        if (<#condition#>) {
//            <#statements#>
//        }
//    }];
//    return [temp copy];
//}


- (void)deleteItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths
{
    NSMutableArray *willUpdateItems = @[].mutableCopy;

    for (NSIndexPath *indexPath in indexPaths) {

        CYCollectionCell *removeCell =  [self removeItemAtIndexPath:indexPath];
        [removeCell removeFromSuperview];

        //移除之后要改变在这个位置之后cell的indexPath
        NSString *key = [NSString stringWithFormat:@"%@%zd", kVisibleCellsKey, indexPath.section];
        NSMutableArray *visibleCells = self.allVisibleCells[key];

        [visibleCells enumerateObjectsUsingBlock:^(CYCollectionCell *obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if (obj.indexPath.section == indexPath.section &&
                obj.indexPath.row > indexPath.row) {
                obj.indexPath = [NSIndexPath indexPathForRow:obj.indexPath.row-1 inSection:obj.indexPath.section];
                [willUpdateItems addObject:obj];
            }
        }];

        //减少一个需要清除 最后一个frame的缓存
    }


    for (CYCollectionCell *cell in willUpdateItems) {
        [self clearItemFrameCacheFromIndexPath:cell.indexPath];
    }

    [self updateItemsFrame:willUpdateItems completion:^{
    }];
    [self updateItemsContainerFrame];
    [self updateContentSize];
}

- (void)updateItemsContainerFrame
{
//    [UIView animateWithDuration:0.3 animations:^{
        for (NSString *key in self.containers.allKeys) {
            NSInteger section = [key integerValue];
            UIView *view = self.containers[key];
            view.frame = [self frameForContainerAtSection:section];
        }
//    }];
}

//- (void)updateItemSupplementViewFrame
//{
//    [UIView animateWithDuration:0.3 animations:^{
//        [self.allSupplementViews enumerateObjectsUsingBlock:^(UIView *obj, NSUInteger idx, BOOL * _Nonnull stop) {
//            NSInteger section = obj.collectionViewSectionIndex;
//            if (section != NSNotFound) {
//                obj.frame = [self frameForItemHeaderAtSection:section];
//            }
//        }];
//    }];
//}

- (void)updateItemsFrame:(NSMutableArray *)willUpdateItems completion:(void(^)(void))completion
{
    //从小到大排序
    [willUpdateItems sortUsingComparator:^NSComparisonResult(CYCollectionCell *obj1, CYCollectionCell *obj2) {
        if (obj1.indexPath.section < obj2.indexPath.section) {
            return NSOrderedAscending;
        }else if (obj1.indexPath.section > obj2.indexPath.section) {
            return NSOrderedDescending;
        }else{
            if (obj1.indexPath.row <= obj2.indexPath.row) {
                return NSOrderedAscending;
            }else{
                return NSOrderedDescending;
            }
        }
    }];

    //更新位置
    [UIView animateWithDuration:0.3 animations:^{

        //item
        [willUpdateItems enumerateObjectsUsingBlock:^(CYCollectionCell *obj, NSUInteger idx, BOOL * _Nonnull stop) {
            obj.frame = [self frameForItemAtIndexPath:obj.indexPath];
        }];

        //TODO: Update Footer View
//        [self.allSupplementViews enumerateObjectsUsingBlock:^(UIView *obj, NSUInteger idx, BOOL * _Nonnull stop) {
//            NSInteger section = obj.collectionViewSectionIndex;
//
//            if (section != NSNotFound) {
//                obj.frame = [self frameForItemHeaderAtSection:section];;
//            }
//        }];

    } completion:^(BOOL finished) {
        completion();
    }];
}

- (void)moveItemAtIndexPath:(NSIndexPath *)indexPath toIndexPath:(NSIndexPath *)newIndexPath
{
    //TODO: ==
    if (indexPath.section == newIndexPath.section) {
        return;
    }

    //过渡效果
    CYCollectionCell *cell = [self removeItemAtIndexPath:indexPath];
    cell.frame = [self.containerView convertRect:cell.frame fromView:cell.superview];
    [self.containerView addSubview:cell];

    NSMutableArray *willUpdateCell = [self moveForwardItemsFromIndexPath:indexPath];

    for (CYCollectionCell *cell in willUpdateCell) {
        [self clearItemFrameCacheFromIndexPath:cell.indexPath];
    }

    [self updateItemsFrame:willUpdateCell completion:^{
    }];

    willUpdateCell = [self moveBackItemsFromIndexPath:newIndexPath];

    cell.indexPath = newIndexPath;

    for (CYCollectionCell *cell in willUpdateCell) {
        [self clearItemFrameCacheFromIndexPath:cell.indexPath];
    }

    [self updateItemsFrame:willUpdateCell completion:^{
    }];

    CGRect toFrame = [self frameForItemAtIndexPath:newIndexPath];
    UIView *toContainerView = [self itemsContainerAtSection:newIndexPath.section];
    toFrame = [self.containerView convertRect:toFrame fromView:toContainerView];

    [UIView animateWithDuration:0.3 animations:^{
        cell.frame = toFrame;
    } completion:^(BOOL finished) {
        [self addGridCell:cell atIndexPath:newIndexPath];
    }];

    [self updateItemsContainerFrame];
    [self updateContentSize];
}

//插入 item 之前移动其后 item 的位置
- (NSMutableArray *)moveBackItemsFromIndexPath:(NSIndexPath *)indexPath
{
    NSMutableArray *willUpdateItems = @[].mutableCopy;

    //插入之前要改变在这个位置之后cell的indexPath
    NSString *key = [NSString stringWithFormat:@"%@%zd", kVisibleCellsKey, indexPath.section];
    NSMutableArray *visibleCells = self.allVisibleCells[key];

    [visibleCells enumerateObjectsUsingBlock:^(CYCollectionCell *obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.indexPath.section == indexPath.section &&
            obj.indexPath.row >= indexPath.row) {
            obj.indexPath = [NSIndexPath indexPathForRow:obj.indexPath.row+1 inSection:obj.indexPath.section];
            [willUpdateItems addObject:obj];
        }
    }];

    //todo:    [self updateItemsFrame:willUpdateItems];
    return willUpdateItems;
}

- (NSMutableArray *)moveForwardItemsFromIndexPath:(NSIndexPath *)indexPath
{
    NSMutableArray *willUpdateItems = @[].mutableCopy;

    //插入之前要改变在这个位置之后cell的indexPath
    NSString *key = [NSString stringWithFormat:@"%@%zd", kVisibleCellsKey, indexPath.section];
    NSMutableArray *visibleCells = self.allVisibleCells[key];

    [visibleCells enumerateObjectsUsingBlock:^(CYCollectionCell *obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.indexPath.section == indexPath.section &&
            obj.indexPath.row >= indexPath.row) {
            obj.indexPath = [NSIndexPath indexPathForRow:obj.indexPath.row-1 inSection:obj.indexPath.section];
            [willUpdateItems addObject:obj];
        }
    }];

    //todo:    [self updateItemsFrame:willUpdateItems];
    return willUpdateItems;
}
@end
