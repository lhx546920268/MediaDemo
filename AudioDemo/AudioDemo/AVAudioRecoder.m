//
//  AVAudioRecoder.m
//  AudioDemo
//
//  Created by 罗海雄 on 2021/11/23.
//

#import "AVAudioRecoder.h"

@import CoreAudio;
@import AudioToolbox;
@import AVFoundation;

static const NSInteger AVAudioRecoderNumberOfBuffers = 3;

typedef struct _AVAudioRecoderState {
    AudioStreamBasicDescription asbd;
    AudioFileID fileID;
    AudioQueueBufferRef buffers[AVAudioRecoderNumberOfBuffers];
    UInt32 bufferByteSize;
    SInt64 currentPacket;
    Boolean recording;
} AVAudioRecoderState;

static void AVAudioRecoderCallback(
 void *nUserData,
 AudioQueueRef inAQ,
 AudioQueueBufferRef inBuffer,
 const AudioTimeStamp *inStartTime,
 UInt32 inNumberPacketDescriptions,
 const AudioStreamPacketDescription *inPacketDescs
 ){
    AVAudioRecoderState *state = (AVAudioRecoderState*)nUserData;

    UInt32 ioNumPackets = inNumberPacketDescriptions;
    UInt32 bytesPerPacket = state->asbd.mBytesPerPacket;
    
    if (ioNumPackets == 0 && bytesPerPacket != 0) {
        //有时候 inNumberPacketDescriptions 会为0
        ioNumPackets = inBuffer->mAudioDataByteSize / bytesPerPacket;
    }
    
    NSLog(@"mBytesPerPacket %d", bytesPerPacket);
    NSLog(@"inNumberPacketDescriptions %d", inNumberPacketDescriptions);
    NSLog(@"ioNumPackets %d", inNumberPacketDescriptions);
    NSLog(@"mAudioDataByteSize %d", inBuffer->mAudioDataByteSize);
    
    if (ioNumPackets > 0) {
        OSStatus status = AudioFileWritePackets(state->fileID, false, inBuffer->mAudioDataByteSize, inPacketDescs, state->currentPacket, &inNumberPacketDescriptions, inBuffer->mAudioData);
        if (status == noErr) {
            state->currentPacket += inNumberPacketDescriptions;
        } else {
            NSLog(@"写入文件失败 error %d", status);
        }
    }
    
    if (state->recording) {
        AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
    }
}

@implementation AVAudioRecoder
{
    AudioQueueRef _queue;
    AudioStreamBasicDescription asbd;
    AVAudioRecoderState _state;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        [AVAudioSession.sharedInstance setActive:YES error:nil];
        asbd.mFormatID = kAudioFormatMPEG4AAC;
        asbd.mFormatFlags = kAudioFormatFlagIsPacked | kLinearPCMFormatFlagIsSignedInteger;
        asbd.mSampleRate = AVAudioSession.sharedInstance.sampleRate;
        asbd.mChannelsPerFrame = MAX(1, (UInt32)AVAudioSession.sharedInstance.inputNumberOfChannels); //有时候返回0
        
        if (asbd.mFormatID == kAudioFormatLinearPCM) {
            UInt32 bytes = asbd.mFormatFlags & kLinearPCMFormatFlagIsSignedInteger ? sizeof(SInt16) : sizeof(Float32);
            asbd.mBitsPerChannel = bytes * 8;
            asbd.mFramesPerPacket = 1;
            asbd.mBytesPerPacket = bytes * asbd.mChannelsPerFrame;
            asbd.mBytesPerFrame = asbd.mBytesPerPacket;
        }
        asbd.mReserved = 0;
    }
    return self;
}

- (BOOL)recording
{
    return _state.recording;
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
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    if (!device) {
        NSLog(@"麦克风不可用");
        return;
    }
    
    [AVAudioSession.sharedInstance requestRecordPermission:^(BOOL granted) {
        if (granted) {
            [self startAfterGuranted];
        } else {
            [self noPermission];
        }
    }];
}

- (void)noPermission
{
    NSLog(@"没有权限");
}

- (void)startAfterGuranted
{
    if (_state.recording) {
        return;
    }
    
    OSStatus status = AudioQueueNewInput(&asbd, AVAudioRecoderCallback, &_state, NULL, kCFRunLoopCommonModes, 0, &_queue);
    if (status != noErr) {
        NSLog(@"录制出错 error %d", status);
        return;
    }
    
    //获取音频格式
    UInt32 size = sizeof(asbd);
    AudioQueueGetProperty(_queue, kAudioQueueProperty_StreamDescription, &asbd, &size);
    if (status != noErr) {
        NSLog(@"获取音频格式失败 error %d", status);
        return;
    }
    
    status = AudioFileCreateWithURL(CFBridgingRetain(self.fileURL), kAudioFileCAFType, &asbd, kAudioFileFlags_EraseFile, &_state.fileID);
    if (status != noErr) {
        NSLog(@"创建文件失败 error %d", status);
        return;
    }
    
    //每个缓冲采样时间
    static const NSTimeInterval duration = 0.1;
    [AVAudioSession.sharedInstance setPreferredIOBufferDuration:duration error:nil];
    
    //计算缓冲大小
    if (asbd.mFormatID == kAudioFormatLinearPCM) {
        _state.bufferByteSize = ceil(asbd.mSampleRate * asbd.mBitsPerChannel / 8 * asbd.mChannelsPerFrame * duration);
    } else {
        _state.bufferByteSize = MAX(1024, asbd.mSampleRate * duration);
    }
    
    _state.asbd = asbd;
    [self setMagicCookieIfNeeded];
    
    //创建缓冲区 3个就够了
    for (NSInteger i = 0; i < AVAudioRecoderNumberOfBuffers; i ++) {
        status = AudioQueueAllocateBuffer(_queue, _state.bufferByteSize, &_state.buffers[i]);
        if (status != noErr) {
            NSLog(@"申请缓冲区出错 error %d", status);
            return;
        }
        
        status = AudioQueueEnqueueBuffer(_queue, _state.buffers[i], 0, NULL);
        
        if (status != noErr) {
            NSLog(@"缓冲区加入队列出错 error %d", status);
            return;
        }
    }
    
    status = AudioQueueStart(_queue, NULL);
    if (status != noErr) {
        NSLog(@"录音启动失败 error %d", status);
        return;
    }
    
    _state.recording = YES;
}

///压缩数据需要设置音频元数据信息 在音频文件开始和结束的时候设置
- (void)setMagicCookieIfNeeded
{
    if (asbd.mFormatID != kAudioFormatLinearPCM) {
        UInt32 size;
        OSStatus status = AudioQueueGetPropertySize(_queue, kAudioQueueProperty_MagicCookie, &size);
        if (status == noErr) {
            void *data = malloc(size);
            status = AudioQueueGetProperty(_queue, kAudioQueueProperty_MagicCookie, data, &size);
            if (status == noErr) {
                status = AudioFileSetProperty(_state.fileID, kAudioFilePropertyMagicCookieData, size, data);
                if (status != noErr) {
                    NSLog(@"设置音频元数据失败");
                }
            }
            free(data);
        }
    }
}

- (void)stop
{
    if (_state.recording) {
        _state.recording = NO;
        AudioQueueFlush(_queue);
        AudioQueueStop(_queue, YES);
        
        [self setMagicCookieIfNeeded];
        
        [self destroy];
    }
}

- (void)destroy
{
    AudioFileClose(_state.fileID);
    
    _state.fileID = NULL;
    _state.bufferByteSize = 0;
    _state.currentPacket = 0;
    
    for (NSInteger i = 0; i < AVAudioRecoderNumberOfBuffers; i ++) {
        AudioQueueFreeBuffer(_queue, _state.buffers[i]);
    }
    
    AudioQueueDispose(_queue, YES);
    _queue = NULL;
}

@end
