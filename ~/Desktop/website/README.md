# Hawala Website

Modern React-based website for the Hawala multi-chain cryptocurrency wallet.

## Tech Stack

- **React 19** with TypeScript
- **Vite** for fast development and building
- **Tailwind CSS** for styling
- **Framer Motion** for animations
- **Lucide React** for icons
- **ESLint + Prettier** for code quality

## Getting Started

### Prerequisites

- Node.js 18+ and npm

### Installation

```bash
npm install
```

### Development

```bash
npm run dev
```

Visit `http://localhost:5173` to see the website.

### Build

```bash
npm run build
```

### Preview Production Build

```bash
npm run preview
```

## Scripts

- `npm run dev` - Start development server
- `npm run build` - Build for production
- `npm run preview` - Preview production build
- `npm run lint` - Run ESLint
- `npm run lint:fix` - Fix ESLint errors
- `npm run format` - Format code with Prettier
- `npm run format:check` - Check code formatting
- `npm run type-check` - Type check without building

## Project Structure

```
website/
├── src/
│   ├── components/     # React components
│   │   ├── ui/        # Base UI components
│   │   └── layout/    # Layout components
│   ├── hooks/         # Custom React hooks
│   ├── utils/         # Utility functions
│   ├── types/         # TypeScript types
│   ├── assets/        # Static assets
│   ├── App.tsx        # Main app component
│   └── main.tsx       # Entry point
├── public/            # Public assets
└── ...config files
```

## Path Aliases

- `@/` → `src/`
- `@components/` → `src/components/`
- `@utils/` → `src/utils/`
- `@hooks/` → `src/hooks/`
- `@types/` → `src/types/`
- `@assets/` → `src/assets/`

## Development

See [WEBSITE_ROADMAP.md](./WEBSITE_ROADMAP.md) for the complete development roadmap.

