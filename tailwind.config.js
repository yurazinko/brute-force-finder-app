/** @type {import('tailwindcss').Config} */
module.exports = {
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        breeze: {
          bg: '#31363b',
          view: '#232629',
          text: '#fcfcfc',
          muted: '#a5a8aa',
          border: '#4d5053',
          accent: '#3daee9',
        }
      },
      keyframes: {
        marquee: {
          '0%': { transform: 'translateX(100%)' },
          '100%': { transform: 'translateX(-100%)' }
        }
      },
      animation: {
        marquee: 'marquee 15s linear infinite'
      }
    },
  },
  plugins: [],
}