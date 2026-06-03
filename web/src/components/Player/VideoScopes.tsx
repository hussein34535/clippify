import { useEffect, useRef } from 'react';

interface VideoScopesProps {
  playerCanvasRef: React.RefObject<HTMLCanvasElement | null>;
  activeScope: 'histogram' | 'waveform' | 'none';
  playing: boolean;
}

export default function VideoScopes({ playerCanvasRef, activeScope, playing }: VideoScopesProps) {
  const scopeCanvasRef = useRef<HTMLCanvasElement>(null);
  const animationRef = useRef<number | null>(null);

  useEffect(() => {
    const scopeCanvas = scopeCanvasRef.current;
    if (!scopeCanvas || activeScope === 'none') {
      if (animationRef.current) cancelAnimationFrame(animationRef.current);
      return;
    }

    const scopeCtx = scopeCanvas.getContext('2d');
    if (!scopeCtx) return;

    const renderScope = () => {
      const playerCanvas = playerCanvasRef.current;
      if (!playerCanvas || !scopeCanvas || !scopeCtx) return;

      const playerCtx = playerCanvas.getContext('2d');
      if (!playerCtx) return;

      try {
        // Read player canvas pixels
        // Sample down to 180x320 for high performance real-time analysis
        
        // Clear scope screen
        scopeCtx.fillStyle = '#0a0a0c';
        scopeCtx.fillRect(0, 0, scopeCanvas.width, scopeCanvas.height);

        // Get player frame pixels
        const imgData = playerCtx.getImageData(0, 0, playerCanvas.width, playerCanvas.height);
        const data = imgData.data;

        if (activeScope === 'histogram') {
          // Compute Histogram
          const rHist = new Uint32Array(256);
          const gHist = new Uint32Array(256);
          const bHist = new Uint32Array(256);
          const lHist = new Uint32Array(256);

          // Step by 4 or 8 pixels for speed
          const step = 4;
          for (let i = 0; i < data.length; i += 4 * step) {
            const r = data[i];
            const g = data[i + 1];
            const b = data[i + 2];
            const l = Math.round(0.299 * r + 0.587 * g + 0.114 * b);

            rHist[r]++;
            gHist[g]++;
            bHist[b]++;
            lHist[l]++;
          }

          // Find max value for normalization
          let maxVal = 1;
          for (let i = 0; i < 256; i++) {
            maxVal = Math.max(maxVal, rHist[i], gHist[i], bHist[i], lHist[i]);
          }

          const scaleX = scopeCanvas.width / 256;
          const scaleY = (scopeCanvas.height - 20) / maxVal;

          // Draw Histogram lines
          const drawChannel = (hist: Uint32Array, color: string) => {
            scopeCtx.strokeStyle = color;
            scopeCtx.lineWidth = 1.2;
            scopeCtx.beginPath();
            for (let i = 0; i < 256; i++) {
              const x = i * scaleX;
              const y = scopeCanvas.height - 5 - hist[i] * scaleY;
              if (i === 0) scopeCtx.moveTo(x, y);
              else scopeCtx.lineTo(x, y);
            }
            scopeCtx.stroke();
          };

          drawChannel(rHist, '#ff453a');
          drawChannel(gHist, '#32d74b');
          drawChannel(bHist, '#0a84ff');
          drawChannel(lHist, 'rgba(255,255,255,0.7)');

          // Draw grid
          scopeCtx.fillStyle = 'rgba(255,255,255,0.2)';
          scopeCtx.font = '8px monospace';
          scopeCtx.fillText('Histogram (RGB+Luma)', 8, 12);
        } 
        else if (activeScope === 'waveform') {
          // Compute Waveform
          // Divide canvas width into columns, draw dots for luma levels in that column
          const cols = 120;
          const stepX = Math.floor(playerCanvas.width / cols);
          const stepY = 6;
          
          scopeCtx.fillStyle = 'rgba(0, 132, 255, 0.05)';
          scopeCtx.lineWidth = 1;

          // Scale factor
          const scopeW = scopeCanvas.width;
          const scopeH = scopeCanvas.height;

          // Draw grid lines
          scopeCtx.strokeStyle = 'rgba(255,255,255,0.1)';
          for (let pct = 0; pct <= 100; pct += 25) {
            const y = scopeH - 10 - (pct / 100) * (scopeH - 20);
            scopeCtx.beginPath();
            scopeCtx.moveTo(0, y);
            scopeCtx.lineTo(scopeW, y);
            scopeCtx.stroke();
            scopeCtx.fillStyle = 'rgba(255,255,255,0.3)';
            scopeCtx.font = '7px monospace';
            scopeCtx.fillText(`${pct}%`, 5, y - 2);
          }

          // Sample pixels and draw Waveform
          for (let col = 0; col < cols; col++) {
            const x = col * stepX;
            const screenX = (col / cols) * scopeW;
            const counts = new Uint8Array(256);

            for (let y = 0; y < playerCanvas.height; y += stepY) {
              const pixelIdx = (y * playerCanvas.width + x) * 4;
              if (pixelIdx < data.length) {
                const r = data[pixelIdx];
                const g = data[pixelIdx + 1];
                const b = data[pixelIdx + 2];
                const l = Math.round(0.299 * r + 0.587 * g + 0.114 * b);
                counts[l]++;
              }
            }

            // Draw column dots
            for (let luma = 0; luma < 256; luma++) {
              if (counts[luma] > 0) {
                const intensity = Math.min(1.0, counts[luma] / 12);
                scopeCtx.fillStyle = `rgba(10, 132, 255, ${intensity * 0.4})`;
                const screenY = scopeH - 10 - (luma / 255) * (scopeH - 20);
                scopeCtx.fillRect(screenX, screenY, scopeW / cols, 1.5);
              }
            }
          }
        }
      } catch (err) {
        // Suppress canvas errors during rapid seeking
      }

      animationRef.current = requestAnimationFrame(renderScope);
    };

    renderScope();

    return () => {
      if (animationRef.current) cancelAnimationFrame(animationRef.current);
    };
  }, [activeScope, playing, playerCanvasRef]);

  if (activeScope === 'none') return null;

  return (
    <div 
      className="rounded-lg overflow-hidden border shadow" 
      style={{ 
        background: '#0a0a0c', 
        borderColor: 'var(--border-subtle)',
        width: '100%',
        height: '110px'
      }}
    >
      <canvas 
        ref={scopeCanvasRef} 
        width={300} 
        height={110} 
        className="w-full h-full object-cover" 
      />
    </div>
  );
}
