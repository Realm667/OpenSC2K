# MP3 decoding fixture

`silence.mp3` is three seconds of generated mono silence (8 kHz, 8 kbit/s).
It contains no third-party recording or original game audio. Generate it with:

```sh
ffmpeg -f lavfi -i anullsrc=r=8000:cl=mono -t 3 -c:a libmp3lame -b:a 8k -map_metadata -1 silence.mp3
```

The music-box regression test copies these bytes to disposable user folders,
then loads them through the external MP3 decoder with the Dummy audio driver.
