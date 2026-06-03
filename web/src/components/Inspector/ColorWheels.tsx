import React, { useRef, useState } from 'react';

interface ColorValue {
  r: number;
  g: number;
  b: number;
}

interface ColorWheelsProps {
  lift: ColorValue;
  gamma: ColorValue;
  gain: ColorValue;
  onChange: (lift: ColorValue, gamma: ColorValue, gain: ColorValue) => void;
}

// Pure helper functions placed outside components
const getXYFromRGB = (val: ColorValue) => {
  // Inverse projection of the RGB shifts
  // Since R = r*cos(t), G = r*cos(t-2pi/3), B = r*cos(t-4pi/3)
  // We can compute x and y vectors:
  const x = val.r - 0.5 * val.g - 0.5 * val.b;
  const y = (Math.sqrt(3) / 2) * (val.g - val.b);
  
  // Normalize to keep it inside the unit circle
  const len = Math.sqrt(x*x + y*y);
  if (len > 0.4) {
    const scale = 0.4 / len;
    return { x: x * scale, y: y * scale };
  }
  return { x, y };
};

const getRGBFromXY = (x: number, y: number): ColorValue => {
  // Project x, y onto RGB axes
  const r = x;
  const g = -0.5 * x + (Math.sqrt(3) / 2) * y;
  const b = -0.5 * x - (Math.sqrt(3) / 2) * y;
  
  return { r: round(r), g: round(g), b: round(b) };
};

const round = (val: number) => Math.round(val * 100) / 100;

interface ColorWheelComponentProps {
  label: string;
  currentVal: ColorValue;
  lumaValue: number;
  lumaMin: number;
  lumaMax: number;
  onWheelChange: (rgb: ColorValue) => void;
  onLumaChange: (luma: number) => void;
}

// Extracted Component to respect React Rules of Hooks
function ColorWheel({
  label,
  currentVal,
  lumaValue,
  lumaMin,
  lumaMax,
  onWheelChange,
  onLumaChange
}: ColorWheelComponentProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [dragging, setDragging] = useState(false);
  const pos = getXYFromRGB(currentVal);

  const handlePointerDown = (e: React.PointerEvent) => {
    setDragging(true);
    updatePosition(e);
    e.currentTarget.setPointerCapture(e.pointerId);
  };

  const handlePointerMove = (e: React.PointerEvent) => {
    if (!dragging) return;
    updatePosition(e);
  };

  const handlePointerUp = (e: React.PointerEvent) => {
    setDragging(false);
    e.currentTarget.releasePointerCapture(e.pointerId);
  };

  const updatePosition = (e: React.PointerEvent) => {
    if (!containerRef.current) return;
    const rect = containerRef.current.getBoundingClientRect();
    const centerX = rect.left + rect.width / 2;
    const centerY = rect.top + rect.height / 2;
    
    // Calculate relative coordinates from center (-1 to 1)
    let rx = (e.clientX - centerX) / (rect.width / 2);
    let ry = (e.clientY - centerY) / (rect.height / 2);
    
    // Enforce circular boundary
    const dist = Math.sqrt(rx*rx + ry*ry);
    if (dist > 1.0) {
      rx /= dist;
      ry /= dist;
    }
    
    // Convert to RGB shifts
    const rgb = getRGBFromXY(rx, -ry); // Invert Y-axis for standard color wheels
    onWheelChange(rgb);
  };

  // Calculate display coords on the wheel (size: 90px diameter, radius: 45px)
  const pointerX = 45 + pos.x * 45;
  const pointerY = 45 - pos.y * 45;

  return (
    <div className="flex flex-col items-center gap-2 flex-1">
      <span className="text-[10px] font-semibold" style={{ color: 'var(--text-secondary)' }}>{label}</span>
      
      {/* The Wheel */}
      <div
        ref={containerRef}
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={handlePointerUp}
        className="w-[90px] h-[90px] rounded-full relative cursor-crosshair border select-none overflow-hidden"
        style={{
          background: 'radial-gradient(circle, rgba(0,0,0,0) 0%, rgba(0,0,0,0.8) 100%), conic-gradient(red, yellow, lime, cyan, blue, magenta, red)',
          borderColor: 'var(--border-default)',
          touchAction: 'none'
        }}
      >
        {/* Center Crosshair */}
        <div className="absolute w-2 h-2 rounded-full border border-white -translate-x-1 -translate-y-1 shadow pointer-events-none"
          style={{
            left: `${pointerX}px`,
            top: `${pointerY}px`,
            background: 'rgba(255,255,255,0.4)',
            boxShadow: '0 0 4px rgba(0,0,0,0.6)'
          }}
        />
      </div>

      {/* Luma Slider */}
      <div className="w-full flex flex-col gap-1 items-center px-1">
        <input
          type="range"
          min={lumaMin}
          max={lumaMax}
          step="0.05"
          value={lumaValue}
          onChange={(e) => onLumaChange(parseFloat(e.target.value))}
          className="w-full h-1 bg-gray-800 rounded-lg appearance-none cursor-pointer"
          style={{ accentColor: 'var(--accent)' }}
        />
        <span className="text-[9px] font-mono" style={{ color: 'var(--text-tertiary)' }}>
          {lumaValue.toFixed(2)}
        </span>
      </div>
    </div>
  );
}

export default function ColorWheels({ lift, gamma, gain, onChange }: ColorWheelsProps) {
  return (
    <div className="flex flex-col gap-4 text-right">
      <div className="flex justify-between items-center gap-3">
        <ColorWheel
          label="Gain (الإضاءة)"
          currentVal={gain}
          lumaValue={gain.r + gain.g + gain.b >= 3 ? 1.0 : (gain.r + gain.g + gain.b) / 3}
          lumaMin={0.5}
          lumaMax={2.0}
          onWheelChange={(rgb) => onChange(lift, gamma, rgb)}
          onLumaChange={(luma) => onChange(lift, gamma, { r: luma, g: luma, b: luma })}
        />
        
        <ColorWheel
          label="Gamma (الظلال)"
          currentVal={gamma}
          lumaValue={gamma.r + gamma.g + gamma.b >= 3 ? 1.0 : (gamma.r + gamma.g + gamma.b) / 3}
          lumaMin={0.2}
          lumaMax={2.5}
          onWheelChange={(rgb) => onChange(lift, rgb, gain)}
          onLumaChange={(luma) => onChange(lift, { r: luma, g: luma, b: luma }, gain)}
        />
        
        <ColorWheel
          label="Lift (التعتيم)"
          currentVal={lift}
          lumaValue={(lift.r + lift.g + lift.b) / 3}
          lumaMin={-0.5}
          lumaMax={0.5}
          onWheelChange={(rgb) => onChange(rgb, gamma, gain)}
          onLumaChange={(luma) => onChange({ r: luma, g: luma, b: luma }, gamma, gain)}
        />
      </div>
    </div>
  );
}
