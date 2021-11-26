//
//  ADAudioPlayer.m
//  AudioDemo
//
//  Created by 罗海雄 on 2021/11/24.
//

#import "ADAudioPlayer.h"

@import CoreAudio;
@import AudioToolbox;
@import AVFoundation;

static const NSInteger ADAudioPlayerNumberOfBuffers = 3;

@interface ADAudioPlayer ()

///是否是可变比特率的格式
@property(nonatomic, readonly) BOOL isVBRFormat;

- (BOOL)readDataToBuffer:(AudioQueueBufferRef) buffer;

@end

typedef struct _ADAudioPlayerState {
    Boolean playing;
    AudioFileID fileID;
    UInt32 bufferSize;
    AudioQueueBufferRef buffers[ADAudioPlayerNumberOfBuffers];
    SInt64 currentPacket;
    UInt32 packetsToRead;
    AudioStreamPacketDescription *packetDesc; //压缩格式才有
} ADAudioPlayerState;

static void ADAudioPlayerCallback(
void *inUserData,
AudioQueueRef inAQ,
AudioQueueBufferRef inBuffer
){
    ADAudioPlayer *player = (ADAudioPlayer*)CFBridgingRelease(inUserData);
    if (player.isPlaying) {
        [player readDataToBuffer:inBuffer];
    }
}

@implementation ADAudioPlayer
{
    AudioQueueRef _queue;
    ADAudioPlayerState _state;
    AudioStreamBasicDescription asbd;
}

- (BOOL)isPlaying
{
    return _state.playing;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        
    }
    return self;
}

- (NSURL *)fileURL
{
    if (!_fileURL) {
        NSString *path = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"test.caf"];
        _fileURL = [NSURL fileURLWithPath:path];
        NSLog(@"file %@", self.fileURL.absoluteString);
    }
    return _fileURL;
}

- (void)start
{
    if (_state.playing) {
        return;
    }
    
    OSStatus status = AudioFileOpenURL(CFBridgingRetain(self.fileURL), kAudioFileReadPermission, 0, &_state.fileID);
    if (status != noErr) {
        NSLog(@"打开音频文件失败 error %d", status);
        return;
    }
    
    UInt32 size = sizeof(asbd);
    status = AudioFileGetProperty(_state.fileID, kAudioFilePropertyDataFormat, &size, &asbd);
    if (status != noErr) {
        NSLog(@"获取音频格式失败 error %d", status);
        return;
    }
    
    status = AudioQueueNewOutput(&asbd, ADAudioPlayerCallback, (void*)CFBridgingRetain(self), NULL, kCFRunLoopCommonModes, 0, &_queue);
    if (status != noErr) {
        NSLog(@"初始化音频播放队列失败 error %d", status);
        return;
    }
    
    [self setMagicCookieIfNeeded];
    
    UInt32 maxPacketSize;
    UInt32 maxPacketDataSize = sizeof(UInt32);
    AudioFileGetProperty(_state.fileID, kAudioFilePropertyPacketSizeUpperBound, &maxPacketDataSize, &maxPacketSize);
    if (maxPacketSize <= 0) {
        maxPacketSize = 4096;
    }
    
    if (asbd.mBytesPerPacket > 0) {
        _state.bufferSize = maxPacketSize * asbd.mBytesPerPacket;
    } else {
        _state.bufferSize = maxPacketSize * 2;
    }
    
    _state.packetsToRead = maxPacketSize;
    if (self.isVBRFormat) {
        _state.packetDesc = malloc(sizeof(_state.packetDesc) * _state.packetsToRead);
    }
    
    for (NSInteger i = 0; i < ADAudioPlayerNumberOfBuffers; i ++) {
        status = AudioQueueAllocateBuffer(_queue, _state.bufferSize, &_state.buffers[i]);
        if (status != noErr) {
            NSLog(@"申请缓冲区失败 error %d", status);
            return;
        }
        
        if (![self readDataToBuffer:_state.buffers[i]]) {
            break;
        }
    }
    
    status = AudioQueueStart(_queue, NULL);
    if (status != noErr) {
        NSLog(@"播放启动失败 error %d", status);
        return;
    }
    
    _state.playing = YES;
}

- (BOOL)readDataToBuffer:(AudioQueueBufferRef) buffer
{
    UInt32 bufferSize = _state.bufferSize;
    UInt32 packetsToRead = _state.packetsToRead;
    OSStatus status = AudioFileReadPacketData(_state.fileID, false, &bufferSize, _state.packetDesc, _state.currentPacket, &packetsToRead, buffer);
    if (status != noErr) {
        NSLog(@"读取音频数据失败 error %d", status);
        return NO;
    }
    
    AudioQueueEnqueueBuffer(_queue, buffer, self.isVBRFormat ? packetsToRead : 0, _state.packetDesc);
    _state.currentPacket += packetsToRead;
    
    return bufferSize != _state.bufferSize && bufferSize > 0;
}

- (void)stop
{
    if (_state.playing) {
        _state.playing = NO;
        AudioQueueStop(_queue, YES);
        
        [self destroy];
    }
}

- (void)destroy
{
    AudioFileClose(_state.fileID);
    
    _state.fileID = NULL;
    _state.currentPacket = 0;
    
    if (_state.packetDesc != NULL) {
        free(_state.packetDesc);
        _state.packetDesc = NULL;
    }
    
    for (NSInteger i = 0; i < ADAudioPlayerNumberOfBuffers; i ++) {
        AudioQueueFreeBuffer(_queue, _state.buffers[i]);
    }
    
    AudioQueueDispose(_queue, YES);
    _queue = NULL;
}

- (BOOL)isVBRFormat
{
    return asbd.mFormatID != kAudioFormatLinearPCM;
}

///压缩数据需要设置音频元数据信息 在音频文件开始和结束的时候设置
- (void)setMagicCookieIfNeeded
{
    if (self.isVBRFormat) {
        UInt32 size;
        OSStatus status = AudioFileGetPropertyInfo(_state.fileID, kAudioFilePropertyMagicCookieData, &size, NULL);
        
        if (status == noErr) {
            void *data = malloc(size);
            status = AudioFileGetProperty(_state.fileID, kAudioFilePropertyMagicCookieData, &size, &data);
            if (status == noErr) {
                status = AudioQueueSetProperty(_queue, kAudioQueueProperty_MagicCookie, data, size);
                if (status != noErr) {
                    NSLog(@"设置音频元数据失败");
                }
            }
            free(data);
        }
    }
}

@end


