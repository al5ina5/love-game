/** @type {import('tailwindcss').Config} */
export default {
    content: [
        "./index.html",
        "./src/**/*.{js,ts,jsx,tsx}",
    ],
    theme: {
        extend: {
            colors: {
                background: '#1a1a1a',
                surface: '#2a2a2a',
                primary: '#3b82f6',
                accent: '#f59e0b',
            }
        },
    },
    plugins: [],
}
