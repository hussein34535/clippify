// comments.ts
// Phase 11 — Collaboration: Comments on timecode/clip.

export interface Comment {
  id: string;
  time: number;        // seconds
  endTime?: number;    // optional range
  clipId?: string;     // optional clip anchor
  author: string;
  text: string;
  createdAt: number;
  resolved?: boolean;
  replies?: Comment[];
}

const STORAGE_KEY = 'clipai_comments';

export function listComments(): Comment[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

export function saveComments(comments: Comment[]) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(comments));
}

export function addComment(text: string, opts: { time: number; endTime?: number; clipId?: string; author?: string }): Comment {
  const comments = listComments();
  const comment: Comment = {
    id: `c_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
    text,
    time: opts.time,
    endTime: opts.endTime,
    clipId: opts.clipId,
    author: opts.author || 'أنت',
    createdAt: Date.now(),
    resolved: false,
    replies: [],
  };
  comments.push(comment);
  saveComments(comments);
  return comment;
}

export function toggleResolved(id: string) {
  const comments = listComments().map((c) =>
    c.id === id ? { ...c, resolved: !c.resolved } : c
  );
  saveComments(comments);
}

export function deleteComment(id: string) {
  saveComments(listComments().filter((c) => c.id !== id));
}

export function addReply(id: string, text: string, author = 'أنت') {
  const comments = listComments().map((c) => {
    if (c.id !== id) return c;
    return {
      ...c,
      replies: [
        ...(c.replies || []),
        {
          id: `r_${Date.now()}`,
          author,
          text,
          createdAt: Date.now(),
        } as any,
      ],
    };
  });
  saveComments(comments);
}
