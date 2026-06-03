"""Motion graphics -- animated titles, lower thirds, outro cards via FFmpeg drawtext."""


def build_title_card_filter(text: str, duration: float) -> list:
    text = text.upper().replace("'", "\\'")
    filters = [
        f"drawtext=text='{text}':fontcolor=white:fontsize=64:fontfile=Impact:"
        f"x='(w-text_w)/2':y='(h-text_h)/2-40':"
        f"enable='between(t,0,{duration})':"
        f"alpha='if(lt(t,0.3),t/0.3,if(gt(t,{duration-0.5}),({duration}-t)/0.5,1))'",
        f"drawtext=text='{text}':fontcolor=yellow:fontsize=64:fontfile=Impact:"
        f"x='(w-text_w)/2+3':y='(h-text_h)/2-37':"
        f"enable='between(t,0,{duration})':"
        f"alpha='if(lt(t,0.3),t/0.3,if(gt(t,{duration-0.5}),({duration}-t)/0.5,1))*0.3'",
    ]
    return filters


def build_lower_third_filter(text: str, start: float, duration: float) -> list:
    text = text.upper().replace("'", "\\'")
    end = start + duration
    filters = [
        f"drawbox=x=0:y='h-80':w='iw':h=80:color=black@0.7:t=fill:enable='between(t,{start},{end})'",
        f"drawtext=text='{text}':fontcolor=white:fontsize=36:fontfile=Arial:"
        f"x='20':y='h-60':enable='between(t,{start},{end})'",
    ]
    return filters
