//
//  ADAudioPlayer.h
//  AudioDemo
//
//  Created by 罗海雄 on 2021/11/24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ADAudioPlayer : NSObject

///
@property(nonatomic, readonly) BOOL isPlaying;

@property(nonatomic, copy, null_resettable) NSURL *fileURL;

- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
