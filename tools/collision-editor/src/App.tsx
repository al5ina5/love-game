import React, { useState, useRef, useEffect, useMemo } from 'react';
import './index.css';

interface Point {
  x: number;
  y: number;
}

interface ImageAsset {
  name: string;
  path: string;
}

function App() {
  const [imageList, setImageList] = useState<ImageAsset[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [imageSrc, setImageSrc] = useState<string | null>(null);
  const [imgDims, setImgDims] = useState<{ w: number; h: number } | null>(null);
  const [points, setPoints] = useState<Point[]>([]);
  const [draggedPointIndex, setDraggedPointIndex] = useState<number | null>(null);

  const [scale, setScale] = useState(1);
  const [pan, setPan] = useState({ x: 0, y: 0 });
  const [isPanning, setIsPanning] = useState(false);
  const [lastMousePos, setLastMousePos] = useState({ x: 0, y: 0 });

  const svgRef = useRef<SVGSVGElement>(null);
  const workspaceRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    fetch('/image-list.json')
      .then(res => res.json())
      .then(data => setImageList(data))
      .catch(err => console.error("Failed to load image list", err));
  }, []);

  const filteredAssets = useMemo(() => {
    return imageList.filter(img =>
      img.name.toLowerCase().includes(searchQuery.toLowerCase())
    );
  }, [imageList, searchQuery]);

  const resetView = (w: number, h: number) => {
    if (!workspaceRef.current) return;
    const availableW = workspaceRef.current.clientWidth;
    const availableH = workspaceRef.current.clientHeight;

    // Default zoom: 80% of available space or huge for pixel art
    let s = Math.min(availableW / w, availableH / h) * 0.8;
    if (w < 64) s = 25; // Tiny icons get 25x
    else if (w < 128) s = Math.max(s, 15);
    else if (w < 256) s = Math.max(s, 8);

    setScale(s);
    setPan({ x: 0, y: 0 });
  };

  const handleImageSelect = (path: string) => {
    const img = new Image();
    img.onload = () => {
      setImgDims({ w: img.naturalWidth, h: img.naturalHeight });
      setImageSrc(path);
      setPoints([
        { x: 1, y: 1 },
        { x: img.naturalWidth - 1, y: 1 },
        { x: img.naturalWidth - 1, y: img.naturalHeight - 1 },
        { x: 1, y: img.naturalHeight - 1 },
      ]);
      // Use requestAnimationFrame for cleaner transition
      requestAnimationFrame(() => resetView(img.naturalWidth, img.naturalHeight));
    };
    img.src = path;
  };

  const handleImageUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      const url = URL.createObjectURL(file);
      handleImageSelect(url);
    }
  };

  const getMousePos = (e: React.MouseEvent | MouseEvent) => {
    if (!svgRef.current) return { x: 0, y: 0 };
    const CTM = svgRef.current.getScreenCTM();
    if (!CTM) return { x: 0, y: 0 };
    return {
      x: (e.clientX - CTM.e) / CTM.a,
      y: (e.clientY - CTM.f) / CTM.d
    };
  };

  const handlePointMouseDown = (index: number, e: React.MouseEvent) => {
    e.stopPropagation();
    if (e.button === 2) {
      e.preventDefault();
      if (points.length > 3) setPoints(points.filter((_, i) => i !== index));
      return;
    }
    setDraggedPointIndex(index);
  };

  const handleLineClick = (index: number, e: React.MouseEvent) => {
    e.stopPropagation();
    const { x, y } = getMousePos(e);
    const newPoints = [...points];
    newPoints.splice(index + 1, 0, { x: Math.round(x), y: Math.round(y) });
    setPoints(newPoints);
    setDraggedPointIndex(index + 1);
  };

  const handleMouseDownMain = (e: React.MouseEvent) => {
    if (e.button === 1 || (e.button === 0 && !e.shiftKey)) {
      setIsPanning(true);
      setLastMousePos({ x: e.clientX, y: e.clientY });
    }
  };

  const handleMouseMove = (e: React.MouseEvent) => {
    if (draggedPointIndex !== null) {
      const { x, y } = getMousePos(e);
      const newPoints = [...points];
      newPoints[draggedPointIndex] = {
        x: Math.max(0, Math.min(Math.round(x), imgDims?.w || 0)),
        y: Math.max(0, Math.min(Math.round(y), imgDims?.h || 0))
      };
      setPoints(newPoints);
    } else if (isPanning) {
      const dx = e.clientX - lastMousePos.x;
      const dy = e.clientY - lastMousePos.y;
      setPan(p => ({ x: p.x + dx, y: p.y + dy }));
      setLastMousePos({ x: e.clientX, y: e.clientY });
    }
  };

  const handleMouseUp = () => {
    setDraggedPointIndex(null);
    setIsPanning(false);
  };

  const handleWheel = (e: React.WheelEvent) => {
    const zoomSensitivity = 0.002;
    const factor = 1 - e.deltaY * zoomSensitivity;
    setScale(Math.max(0.01, Math.min(100, scale * factor)));
  };

  const copyToClipboard = () => {
    navigator.clipboard.writeText(JSON.stringify(points, null, 2))
      .then(() => alert('Points copied!'))
      .catch(err => console.error('Failed to copy', err));
  };

  return (
    <div className="flex h-screen w-screen bg-[#020202] text-gray-100 font-sans overflow-hidden" onContextMenu={e => e.preventDefault()}>
      {/* Sidebar: Strictly constrained width */}
      <div className="w-80 min-w-[320px] max-w-[320px] flex-shrink-0 bg-gray-900 border-r border-gray-800 flex flex-col z-20 shadow-2xl h-full">
        <div className="p-4 border-b border-gray-800 bg-gray-900/80 backdrop-blur-xl">
          <h1 className="text-xl font-black italic tracking-tighter bg-gradient-to-br from-blue-400 via-blue-100 to-indigo-600 bg-clip-text text-transparent mb-4">
            MASK EDITOR v2
          </h1>
          <input
            type="text"
            placeholder="Search assets..."
            className="w-full bg-black/40 border border-white/10 rounded-lg px-3 py-2 text-xs focus:ring-1 focus:ring-blue-500 outline-none mb-3 font-mono"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
          <label className="block w-full text-center cursor-pointer px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-lg text-[10px] font-black tracking-widest transition-all active:scale-95 uppercase">
            Upload Custom
            <input type="file" onChange={handleImageUpload} className="hidden" accept="image/*" />
          </label>
        </div>

        <div className="flex-1 overflow-y-auto p-2 space-y-1 scroll-smooth">
          <p className="text-[9px] font-black text-gray-600 px-3 uppercase tracking-[0.2em] mb-3 mt-2">
            Files ({filteredAssets.length})
          </p>
          {filteredAssets.map((img) => (
            <button
              key={img.path}
              onClick={() => handleImageSelect(img.path)}
              className={`w-full text-left px-3 py-2 rounded-lg text-[11px] transition-all group overflow-hidden ${imageSrc === img.path ? 'bg-blue-600 text-white shadow-lg' : 'text-gray-500 hover:bg-gray-800/80 hover:text-gray-300'}`}
              title={img.name}
            >
              <div className="truncate font-bold">{img.name.split('/').pop()}</div>
              <div className="text-[8px] opacity-40 italic truncate mt-0.5 group-hover:opacity-70">{img.name.split('/').slice(0, -1).join('/')}</div>
            </button>
          ))}
          {filteredAssets.length === 0 && (
            <div className="text-xs text-center py-12 text-gray-700 font-bold uppercase tracking-widest italic">No matches</div>
          )}
        </div>

        <div className="p-4 border-t border-gray-800 bg-black/20 space-y-3">
          <button
            onClick={copyToClipboard}
            disabled={!imageSrc}
            className="w-full px-4 py-3 bg-white text-black hover:bg-gray-200 disabled:opacity-20 rounded-xl text-xs font-black transition-all shadow-xl active:scale-95 uppercase tracking-widest"
          >
            Copy JSON
          </button>
          <button
            onClick={() => imgDims && resetView(imgDims.w, imgDims.h)}
            className="w-full px-4 py-2 bg-gray-800 hover:bg-gray-700 text-gray-400 rounded-lg text-[9px] font-bold uppercase transition-colors"
          >
            Recenter
          </button>
        </div>
      </div>

      {/* Workspace Area: flex-1 ensures it takes the remaining space */}
      <div
        ref={workspaceRef}
        className="flex-1 relative bg-[#050505] checkered-bg overflow-hidden select-none cursor-crosshair flex items-center justify-center"
        onMouseDown={handleMouseDownMain}
        onMouseMove={handleMouseMove}
        onMouseUp={handleMouseUp}
        onMouseLeave={handleMouseUp}
        onWheel={handleWheel}
      >
        {imageSrc && imgDims ? (
          <div
            style={{
              position: 'relative',
              width: imgDims.w,
              height: imgDims.h,
              transform: `translate(${pan.x}px, ${pan.y}px) scale(${scale})`,
              transition: isPanning ? 'none' : 'transform 0.1s ease-out',
              transformOrigin: 'center center',
              willChange: 'transform'
            }}
          >
            <svg
              ref={svgRef}
              viewBox={`0 0 ${imgDims.w} ${imgDims.h}`}
              style={{ width: '100%', height: '100%', overflow: 'visible' }}
              className="shadow-[0_0_80px_rgba(0,0,0,0.9)] bg-black/40"
            >
              <image
                href={imageSrc}
                width={imgDims.w}
                height={imgDims.h}
                style={{ imageRendering: 'pixelated' }}
              />

              <polygon
                points={points.map(p => `${p.x},${p.y}`).join(' ')}
                fill="rgba(59, 130, 246, 0.2)"
                stroke="#3b82f6"
                strokeWidth={1 / scale}
                className="pointer-events-none"
              />

              {/* Visual Lines and Splitters */}
              {points.map((p, i) => {
                const nextP = points[(i + 1) % points.length];
                return (
                  <React.Fragment key={`l-${i}`}>
                    <line
                      x1={p.x} y1={p.y} x2={nextP.x} y2={nextP.y}
                      stroke="transparent"
                      strokeWidth={12 / scale}
                      className="cursor-crosshair pointer-events-auto hover:stroke-white/10"
                      onMouseDown={(e) => handleLineClick(i, e)}
                    />
                    <line
                      x1={p.x} y1={p.y} x2={nextP.x} y2={nextP.y}
                      stroke="#3b82f6"
                      strokeWidth={1.2 / scale}
                      className="pointer-events-none"
                    />
                  </React.Fragment>
                )
              })}

              {/* Nodes */}
              {points.map((p, i) => (
                <g
                  key={`p-${i}`}
                  onMouseDown={(e) => handlePointMouseDown(i, e)}
                  className="cursor-move pointer-events-auto"
                >
                  <circle cx={p.x} cy={p.y} r={10 / scale} fill="transparent" />
                  <circle
                    cx={p.x} cy={p.y}
                    r={4 / scale}
                    fill={draggedPointIndex === i ? '#f59e0b' : 'rgba(255, 255, 255, 0.6)'}
                    stroke={draggedPointIndex === i ? '#f59e0b' : 'white'}
                    strokeWidth={1 / scale}
                  />
                  {/* Precision dot */}
                  <circle cx={p.x} cy={p.y} r={0.5 / scale} fill="black" />
                </g>
              ))}
            </svg>
          </div>
        ) : (
          <div className="flex flex-col items-center gap-6 opacity-10 select-none">
            <h2 className="text-8xl font-black italic tracking-tighter">EDITOR</h2>
            <div className="flex gap-4 items-center">
              <div className="w-12 h-px bg-white" />
              <p className="text-sm font-mono uppercase tracking-[1em]">Select an asset</p>
              <div className="w-12 h-px bg-white" />
            </div>
          </div>
        )}

        {/* HUD Info */}
        {imgDims && (
          <div className="absolute top-6 right-6 flex items-center gap-6 bg-gray-950/90 backdrop-blur-2xl border border-white/5 rounded-2xl px-6 py-4 shadow-2xl z-30 pointer-events-none transform transition-all animate-in fade-in slide-in-from-top-4">
            <div className="flex flex-col">
              <span className="text-[10px] text-gray-600 font-bold uppercase tracking-widest mb-1">Asset Info</span>
              <span className="text-sm font-mono text-blue-400">{imgDims.w} × {imgDims.h}px</span>
            </div>
            <div className="w-px h-8 bg-white/10" />
            <div className="flex flex-col">
              <span className="text-[10px] text-gray-600 font-bold uppercase tracking-widest mb-1">Workspace</span>
              <span className="text-sm font-mono text-white">{(scale * 100).toFixed(0)}% zoom</span>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

export default App;
