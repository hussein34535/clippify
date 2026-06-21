import os
import cv2

def get_video_info(video_path):
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return 30.0, 1920, 1080
    
    fps = cap.get(cv2.CAP_PROP_FPS)
    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    cap.release()
    
    if fps <= 0:
        fps = 30.0
    return fps, w, h

def sec_to_frames(sec, fps):
    return int(round(sec * fps))

def export_fcp_xml(video_path, clips, output_xml_path):
    """
    Generates an FCP-7 XML file for DaVinci Resolve import.
    `clips` is a list of dictionaries: [{'start_sec': float, 'end_sec': float}, ...]
    """
    fps, width, height = get_video_info(video_path)
    
    # NTSC flag handling
    ntsc = "TRUE" if abs(fps - 29.97) < 0.1 or abs(fps - 23.976) < 0.1 else "FALSE"
    timebase = int(round(fps))

    # Basic XML header
    xml = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<!DOCTYPE xmeml>',
        '<xmeml version="5">',
        '  <sequence id="Clippify_Timeline">',
        '    <name>Clippify Auto-Edited Timeline</name>',
        '    <duration>90000</duration>',
        '    <rate>',
        f'      <timebase>{timebase}</timebase>',
        f'      <ntsc>{ntsc}</ntsc>',
        '    </rate>',
        '    <media>',
        '      <video>',
        '        <format>',
        '          <samplecharacteristics>',
        f'            <width>{width}</width>',
        f'            <height>{height}</height>',
        '            <pixelaspectratio>square</pixelaspectratio>',
        '          </samplecharacteristics>',
        '        </format>',
        '        <track>'
    ]

    # Add Video Clips
    timeline_current_frame = 0
    file_id = "SourceVideoFile"
    
    for i, clip in enumerate(clips):
        start_f = sec_to_frames(clip['start_sec'], fps)
        end_f = sec_to_frames(clip['end_sec'], fps)
        dur_f = end_f - start_f
        
        xml.extend([
            f'          <clipitem id="vclip_{i}">',
            f'            <name>Clip_{i+1}</name>',
            f'            <duration>{dur_f}</duration>',
            f'            <rate><timebase>{timebase}</timebase><ntsc>{ntsc}</ntsc></rate>',
            f'            <start>{timeline_current_frame}</start>',
            f'            <end>{timeline_current_frame + dur_f}</end>',
            f'            <in>{start_f}</in>',
            f'            <out>{end_f}</out>',
            '            <file id="' + file_id + '">',
            f'              <name>{os.path.basename(video_path)}</name>',
            f'              <pathurl>file://localhost/{video_path.replace(chr(92), "/")}</pathurl>',
            f'              <rate><timebase>{timebase}</timebase><ntsc>{ntsc}</ntsc></rate>',
            '              <media>',
            '                <video><duration>90000</duration></video>',
            '                <audio><channelcount>2</channelcount></audio>',
            '              </media>',
            '            </file>',
            '          </clipitem>'
        ])
        timeline_current_frame += dur_f
        
    xml.extend([
        '        </track>',
        '      </video>',
        '      <audio>',
        '        <track>'
    ])

    # Add Audio Clips (Track 1)
    timeline_current_frame = 0
    for i, clip in enumerate(clips):
        start_f = sec_to_frames(clip['start_sec'], fps)
        end_f = sec_to_frames(clip['end_sec'], fps)
        dur_f = end_f - start_f
        
        xml.extend([
            f'          <clipitem id="aclip_ch1_{i}">',
            f'            <name>Clip_{i+1} Audio</name>',
            f'            <duration>{dur_f}</duration>',
            f'            <rate><timebase>{timebase}</timebase><ntsc>{ntsc}</ntsc></rate>',
            f'            <start>{timeline_current_frame}</start>',
            f'            <end>{timeline_current_frame + dur_f}</end>',
            f'            <in>{start_f}</in>',
            f'            <out>{end_f}</out>',
            '            <file id="' + file_id + '"/>',
            '            <sourcetrack><mediatype>audio</mediatype><trackindex>1</trackindex></sourcetrack>',
            '          </clipitem>'
        ])
        timeline_current_frame += dur_f

    xml.extend([
        '        </track>',
        '        <track>'
    ])

    # Add Audio Clips (Track 2 - stereo)
    timeline_current_frame = 0
    for i, clip in enumerate(clips):
        start_f = sec_to_frames(clip['start_sec'], fps)
        end_f = sec_to_frames(clip['end_sec'], fps)
        dur_f = end_f - start_f
        
        xml.extend([
            f'          <clipitem id="aclip_ch2_{i}">',
            f'            <name>Clip_{i+1} Audio</name>',
            f'            <duration>{dur_f}</duration>',
            f'            <rate><timebase>{timebase}</timebase><ntsc>{ntsc}</ntsc></rate>',
            f'            <start>{timeline_current_frame}</start>',
            f'            <end>{timeline_current_frame + dur_f}</end>',
            f'            <in>{start_f}</in>',
            f'            <out>{end_f}</out>',
            '            <file id="' + file_id + '"/>',
            '            <sourcetrack><mediatype>audio</mediatype><trackindex>2</trackindex></sourcetrack>',
            '          </clipitem>'
        ])
        timeline_current_frame += dur_f

    xml.extend([
        '        </track>',
        '      </audio>',
        '    </media>',
        '  </sequence>',
        '</xmeml>'
    ])

    xml_content = "\n".join(xml)
    with open(output_xml_path, 'w', encoding='utf-8') as f:
        f.write(xml_content)
    
    print(f"  [XML Export] FCP-7 XML generated successfully at: {output_xml_path}")
    return output_xml_path


def export_timeline_to_fcp_xml(timeline: dict, output_xml_path: str) -> str:
    """
    Exports a complex TimelineState JSON to an FCP-7 XML for DaVinci Resolve / Premiere Pro import.
    """
    settings = timeline.get("settings", {})
    width = settings.get("width", 1080)
    height = settings.get("height", 1920)
    fps = settings.get("fps", 30)
    
    ntsc = "TRUE" if abs(fps - 29.97) < 0.1 or abs(fps - 23.976) < 0.1 else "FALSE"
    timebase = int(round(fps))
    
    tracks = timeline.get("tracks", {})
    video_tracks = tracks.get("video", [])
    audio_tracks = tracks.get("audio", [])
    overlay_tracks = tracks.get("overlays", [])
    s_tracks = tracks.get("subtitles", [])
    
    xml = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<!DOCTYPE xmeml>',
        '<xmeml version="5">',
        '  <sequence id="Clippify_NLE_Timeline">',
        f'    <name>{timeline.get("project_name", "Clippify Pro NLE Project")}</name>',
        '    <rate>',
        f'      <timebase>{timebase}</timebase>',
        f'      <ntsc>{ntsc}</ntsc>',
        '    </rate>',
        '    <media>',
        '      <video>',
        '        <format>',
        '          <samplecharacteristics>',
        f'            <width>{width}</width>',
        f'            <height>{height}</height>',
        '            <pixelaspectratio>square</pixelaspectratio>',
        '          </samplecharacteristics>',
        '        </format>'
    ]
    
    # Process Video Tracks
    v_track_index = 1
    for track in video_tracks + overlay_tracks:
        xml.append(f'        <track>')
        for idx, clip in enumerate(track.get("clips", [])):
            v_path = clip.get("source_path", "")
            t_start = clip.get("start_time_in_timeline", 0.0)
            t_end = clip.get("end_time_in_timeline", 5.0)
            trim_start = clip.get("source_trim_start", 0.0)
            trim_end = clip.get("source_trim_end", 5.0)
            
            start_f = sec_to_frames(t_start, fps)
            end_f = sec_to_frames(t_end, fps)
            in_f = sec_to_frames(trim_start, fps)
            out_f = sec_to_frames(trim_end, fps)
            dur_f = end_f - start_f
            
            clip_id = f"v_{clip.get('id', idx)}"
            xml.extend([
                f'          <clipitem id="{clip_id}">',
                f'            <name>{os.path.basename(v_path) or "Clip"}</name>',
                f'            <duration>{dur_f}</duration>',
                f'            <rate><timebase>{timebase}</timebase><ntsc>{ntsc}</ntsc></rate>',
                f'            <start>{start_f}</start>',
                f'            <end>{end_f}</end>',
                f'            <in>{in_f}</in>',
                f'            <out>{out_f}</out>',
                f'            <file id="file_{clip_id}">',
                f'              <name>{os.path.basename(v_path)}</name>',
                f'              <pathurl>file://localhost/{v_path.replace(chr(92), "/")}</pathurl>',
                f'              <rate><timebase>{timebase}</timebase><ntsc>{ntsc}</ntsc></rate>',
                '              <media>',
                '                <video><duration>90000</duration></video>',
                '                <audio><channelcount>2</channelcount></audio>',
                '              </media>',
                '            </file>',
                '          </clipitem>'
            ])
        xml.append(f'        </track>')
        v_track_index += 1
        
    xml.extend([
        '      </video>',
        '      <audio>'
    ])
    
    # Process Audio Tracks
    for track in audio_tracks:
        xml.append('        <track>')
        for idx, clip in enumerate(track.get("clips", [])):
            a_path = clip.get("source_path", "")
            t_start = clip.get("start_time_in_timeline", 0.0)
            t_end = clip.get("end_time_in_timeline", 5.0)
            trim_start = clip.get("source_trim_start", 0.0)
            trim_end = clip.get("source_trim_end", 5.0)
            
            start_f = sec_to_frames(t_start, fps)
            end_f = sec_to_frames(t_end, fps)
            in_f = sec_to_frames(trim_start, fps)
            out_f = sec_to_frames(trim_end, fps)
            dur_f = end_f - start_f
            
            clip_id = f"a_{clip.get('id', idx)}"
            xml.extend([
                f'          <clipitem id="{clip_id}">',
                f'            <name>{os.path.basename(a_path) or "Audio"}</name>',
                f'            <duration>{dur_f}</duration>',
                f'            <rate><timebase>{timebase}</timebase><ntsc>{ntsc}</ntsc></rate>',
                f'            <start>{start_f}</start>',
                f'            <end>{end_f}</end>',
                f'            <in>{in_f}</in>',
                f'            <out>{out_f}</out>',
                f'            <file id="file_{clip_id}">',
                f'              <name>{os.path.basename(a_path)}</name>',
                f'              <pathurl>file://localhost/{a_path.replace(chr(92), "/")}</pathurl>',
                f'              <rate><timebase>{timebase}</timebase><ntsc>{ntsc}</ntsc></rate>',
                '              <media>',
                '                <audio><channelcount>2</channelcount></audio>',
                '              </media>',
                '            </file>',
                '          </clipitem>'
            ])
        xml.append('        </track>')

    xml.extend([
        '      </audio>',
        '    </media>'
    ])

    # ── Subtitle → Yellow Markers ──────────────────────────────────────────
    xml.append('    <markers>')
    for s_track in s_tracks:
        for sub in s_track.get("clips", []):
            t_in  = sub.get("start_time", sub.get("start_time_in_timeline", 0))
            text  = sub.get("text", "").replace('"', "'")[:80]
            frame = sec_to_frames(t_in, fps)
            xml.extend([
                '      <marker>',
                f'        <name>{text}</name>',
                f'        <in>{frame}</in>',
                '        <color>yellow</color>',
                '        <comment>Clippify Caption</comment>',
                '      </marker>',
            ])
    xml.append('    </markers>')
    xml.extend([
        '  </sequence>',
        '</xmeml>'
    ])

    content = "\n".join(xml)
    with open(output_xml_path, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"  [XML Export] Saved → {output_xml_path}")
    return output_xml_path
