//
//  WebRTCModule+RTCMediaStream.m
//
//  Created by one on 2015/9/24.
//  Copyright © 2015 One. All rights reserved.
//

#import <objc/runtime.h>

#import "RTCVideoCapturer.h"
#import "RTCVideoSource.h"
#import "RTCVideoTrack.h"
#import "RTCPair.h"
#import "RTCMediaConstraints.h"

#import "WebRTCModule+RTCMediaStream.h"
#import "WebRTCModule+RTCPeerConnection.h"

@implementation RTCMediaStream (React)
- (NSNumber *)reactTag {
  return objc_getAssociatedObject(self, _cmd);
}
- (void)setReactTag:(NSNumber *)reactTag {
  objc_setAssociatedObject(self, @selector(reactTag), reactTag, OBJC_ASSOCIATION_COPY_NONATOMIC);
}
@end

@implementation RTCVideoTrack (React)
- (NSNumber *)reactTag{
  return objc_getAssociatedObject(self, _cmd);
}
- (void)setReactTag:(NSNumber *)reactTag {
  objc_setAssociatedObject(self, @selector(reactTag), reactTag, OBJC_ASSOCIATION_COPY_NONATOMIC);
}
@end

@implementation RTCAudioTrack (React)
- (NSNumber *)reactTag {
  return objc_getAssociatedObject(self, _cmd);
}
- (void)setReactTag:(NSNumber *)reactTag {
  objc_setAssociatedObject(self, @selector(reactTag), reactTag, OBJC_ASSOCIATION_COPY_NONATOMIC);
}
@end

@implementation AVCaptureDevice (React)

- (NSString*)positionString {
  switch (self.position) {
    case AVCaptureDevicePositionUnspecified: return @"unspecified";
    case AVCaptureDevicePositionBack: return @"back";
    case AVCaptureDevicePositionFront: return @"front";
  }
  return nil;
}

@end

@implementation WebRTCModule (RTCMediaStream)

RCT_EXPORT_METHOD(getUserMedia:(NSDictionary *)constraints callback:(RCTResponseSenderBlock)callback)
{
  NSNumber *objectID = @(self.mediaStreamId++);
  
  NSMutableArray *tracks = [NSMutableArray array];

  // Initialize RTCMediaStream with a unique label in order to allow multiple
  // RTCMediaStream instances initialized by multiple getUserMedia calls to be
  // added to 1 RTCPeerConnection instance. As suggested by
  // https://www.w3.org/TR/mediacapture-streams/#mediastream to be a good
  // practice, use a UUID (conforming to RFC4122).
  NSString *mediaStreamUUID = [[NSUUID UUID] UUIDString];
  RTCMediaStream *mediaStream = [self.peerConnectionFactory mediaStreamWithLabel:mediaStreamUUID];

  if (constraints[@"audio"] && [constraints[@"audio"] boolValue]) {
    RTCAudioTrack *audioTrack = [self.peerConnectionFactory audioTrackWithID:@"ARDAMSa0"];
    [mediaStream addAudioTrack:audioTrack];
    NSNumber *trackId = @(self.trackId++);
    audioTrack.reactTag = trackId;
    self.tracks[trackId] = audioTrack;
    [tracks addObject:@{@"id": trackId, @"kind": audioTrack.kind, @"label": audioTrack.label, @"enabled": @(audioTrack.isEnabled), @"remote": @(NO), @"readyState": @"live"}];
  }

  if (constraints[@"video"]) {
    AVCaptureDevice *videoDevice;
    if ([constraints[@"video"] isKindOfClass:[NSNumber class]]) {
      if ([constraints[@"video"] boolValue]) {
        videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
      }
    } else if ([constraints[@"video"] isKindOfClass:[NSDictionary class]]) {
      if (constraints[@"video"][@"optional"]) {
        if ([constraints[@"video"][@"optional"] isKindOfClass:[NSArray class]]) {
          NSArray *options = constraints[@"video"][@"optional"];
          for (id item in options) {
            if ([item isKindOfClass:[NSDictionary class]]) {
              NSDictionary *dict = item;
              if (dict[@"sourceId"]) {
                videoDevice = [AVCaptureDevice deviceWithUniqueID:dict[@"sourceId"]];
              }
            }
          }
        }
      }
      if (!videoDevice) {
        videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
      }
    }
    
    if (videoDevice) {
      RTCVideoCapturer *capturer = [RTCVideoCapturer capturerWithDeviceName:[videoDevice localizedName]];
      RTCVideoSource *videoSource = [self.peerConnectionFactory videoSourceWithCapturer:capturer constraints:[self defaultMediaStreamConstraints]];
      RTCVideoTrack *videoTrack = [self.peerConnectionFactory videoTrackWithID:@"ARDAMSv0" source:videoSource];
      [mediaStream addVideoTrack:videoTrack];
      NSNumber *trackId = @(self.trackId++);
      videoTrack.reactTag = trackId;
      self.tracks[trackId] = videoTrack;
      [tracks addObject:@{@"id": trackId, @"kind": videoTrack.kind, @"label": videoTrack.label, @"enabled": @(videoTrack.isEnabled), @"remote": @(NO), @"readyState": @"live"}];

    }
  }

  mediaStream.reactTag = objectID;
  self.mediaStreams[objectID] = mediaStream;
  callback(@[objectID, tracks]);
}

RCT_EXPORT_METHOD(mediaStreamTrackGetSources:(RCTResponseSenderBlock)callback) {
  NSMutableArray *sources = [NSMutableArray array];
  NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
  for (AVCaptureDevice *device in videoDevices) {
    [sources addObject:@{
                         @"facing": device.positionString,
                         @"id": device.uniqueID,
                         @"label": device.localizedName,
                         @"kind": @"video",
                         }];
  }
  NSArray *audioDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio];
  for (AVCaptureDevice *device in audioDevices) {
    [sources addObject:@{
                         @"facing": @"",
                         @"id": device.uniqueID,
                         @"label": device.localizedName,
                         @"kind": @"audio",
                         }];
  }
  callback(@[sources]);
}

RCT_EXPORT_METHOD(mediaStreamTrackStop:(nonnull NSNumber *)trackID)
{
  RTCMediaStreamTrack *track = self.tracks[trackID];
  if (track) {
    [track setEnabled:NO];
    if ([track.kind isEqualToString:@"audio"]) {
      RTCAudioTrack *audioTrack = self.tracks[trackID];
      [self.tracks removeObjectForKey:audioTrack.reactTag];
    } else if([track.kind isEqualToString:@"video"]) {
      RTCVideoTrack *videoTrack = self.tracks[trackID];
      [self.tracks removeObjectForKey:videoTrack.reactTag];
    }
  }
}

RCT_EXPORT_METHOD(mediaStreamTrackSetEnabled:(nonnull NSNumber *)trackID : (BOOL *)enabled)
{
  RTCMediaStreamTrack *track = self.tracks[trackID];
  if (track && track.isEnabled != enabled) {
    [track setEnabled:enabled];
  }
}

RCT_EXPORT_METHOD(mediaStreamTrackRelease:(nonnull NSNumber *)streamID : (nonnull NSNumber *)trackID)
{
  // what's different to mediaStreamTrackStop? only call mediaStream explicitly?
  if (self.mediaStreams[streamID] && self.tracks[trackID]) {
    RTCMediaStream *mediaStream = self.mediaStreams[streamID];
    RTCMediaStreamTrack *track = self.tracks[trackID];
    [track setEnabled:NO];
    if ([track.kind isEqualToString:@"audio"]) {
      RTCAudioTrack *audioTrack = self.tracks[trackID];
      [self.tracks removeObjectForKey:audioTrack.reactTag];
      [mediaStream removeAudioTrack:audioTrack];
    } else if([track.kind isEqualToString:@"video"]) {
      RTCVideoTrack *videoTrack = self.tracks[trackID];
      [self.tracks removeObjectForKey:videoTrack.reactTag];
      [mediaStream removeVideoTrack:videoTrack];
    }
  }
}

RCT_EXPORT_METHOD(mediaStreamRelease:(nonnull NSNumber *)streamID)
{
  if (self.mediaStreams[streamID]) {
    RTCMediaStream *mediaStream = self.mediaStreams[streamID];
    for (RTCVideoTrack *track in mediaStream.videoTracks) {
      [self.tracks removeObjectForKey:track.reactTag];
    }
    for (RTCAudioTrack *track in mediaStream.audioTracks) {
      [self.tracks removeObjectForKey:track.reactTag];
    }
    [self.mediaStreams removeObjectForKey:streamID];
  }
}
- (RTCMediaConstraints *)defaultMediaStreamConstraints {
    RTCPair *maxWidth = [[RTCPair alloc] initWithKey:@"maxWidth" value:@"480"];
    RTCPair *maxHeight = [[RTCPair alloc] initWithKey:@"maxHeight" value:@"320"];
    RTCPair *maxFrameRate = [[RTCPair alloc] initWithKey:@"maxFrameRate" value:@"15"];//doesn't work.
    //RTCPair *maxWidth = [[RTCPair alloc] initWithKey:@"maxWidth" value:@"640"];
    //RTCPair *maxHeight = [[RTCPair alloc] initWithKey:@"maxHeight" value:@"480"];
  RTCMediaConstraints* constraints =
  [[RTCMediaConstraints alloc]
   initWithMandatoryConstraints:@[maxWidth,maxHeight]
   optionalConstraints:nil];
  return constraints;
}

@end
