from PIL import Image, ImageDraw
from customtkinter import CTkImage


def create_copy_icon(size=(18, 18), color=(142, 142, 147), accent=None):
    """Draw a crisp two-pages copy icon."""
    w, h = size
    r = max(2, int(w * 0.14))  # corner radius
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    if accent:
        c = accent
    else:
        c = color

    # back sheet (offset up+right, slightly dimmer)
    bx, by = int(w * 0.30), int(h * 0.12)
    bw, bh = int(w * 0.58), int(h * 0.72)
    draw.rounded_rectangle(
        [bx, by, bx + bw - 1, by + bh - 1],
        radius=r,
        fill=(*c, 120), outline=(*c, 180), width=1,
    )

    # front sheet (main layer)
    fx, fy = int(w * 0.14), int(h * 0.28)
    fw, fh = int(w * 0.58), int(h * 0.72)
    draw.rounded_rectangle(
        [fx, fy, fx + fw - 1, fy + fh - 1],
        radius=r,
        fill=(*c, 200), outline=(*c, 255), width=1,
    )
    return img


def get_copy_icon(size=(18, 18), color=(142, 142, 147), accent=None):
    """Return a CTkImage for use with CTk widgets."""
    img = create_copy_icon(size, color, accent)
    return CTkImage(light_image=img, dark_image=img, size=size)
