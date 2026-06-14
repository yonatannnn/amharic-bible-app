import type { NextConfig } from "next";

const BIBLE_API =
  process.env.NEXT_PUBLIC_BIBLE_API ??
  "https://faithful-marni-anatoli-b7663357.koyeb.app";

const nextConfig: NextConfig = {
  async rewrites() {
    return [
      // Same-origin proxy to the no-CORS Amharic Bible content API.
      { source: "/bible-api/:path*", destination: `${BIBLE_API}/:path*` },
    ];
  },
};

export default nextConfig;
