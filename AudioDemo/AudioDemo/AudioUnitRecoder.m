//
//  AudioUnitRecoder.m
//  AudioDemo
//
//  Created by 罗海雄 on 2021/11/26.
//

#import "AudioUnitRecoder.h"

@import AudioUnit;
@import AudioToolbox;

@implementation AudioUnitRecoder

- (instancetype)init
{
    self = [super init];
    if (self) {
        AUGraph processingGraph;
        NewAUGraph(&processingGraph);
        kAudioOutputUnitProperty_EnableIO;
    }
    return self;
}

@end
