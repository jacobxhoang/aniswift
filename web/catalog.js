const anime = (id, title, alt, image, score, total, genres, synopsis) => ({ id, title, alt, image, score, total, genres, synopsis, kind: 'anime', type: 'TV' });
const manga = (id, title, alt, image, score, total, genres, synopsis) => ({ id, title, alt, image, score, total, genres, synopsis, kind: 'manga', type: 'Manga' });
const tmdb = (file) => `https://image.tmdb.org/t/p/w500/${file}`;

export const featured = [
  anime(52991, 'Frieren: Beyond Journey’s End', 'Sousou no Frieren', 'https://www.manga-news.com/public/images/dvd/Frieren_S1_anime.jpg', 9.3, 28, ['Adventure', 'Fantasy'], 'After her party defeats the Demon King, an elven mage starts a new journey to understand the lives she once hurried past.'),
  anime(54492, 'The Apothecary Diaries', 'Kusuriya no Hitorigoto', tmdb('7qx7OwBZcI0dRWc8DrbtxY5IrlV.jpg'), 8.9, 24, ['Drama', 'Mystery'], 'A gifted apothecary puts her knowledge of medicine and poisons to work solving mysteries in the imperial court.'),
  anime(57334, 'DAN DA DAN', 'Dandadan', tmdb('bSw03RorPe5LvmcIkXVgSUAAk8G.jpg'), 8.4, 12, ['Action', 'Supernatural'], 'Two teens try to prove each other wrong about aliens and ghosts, and stumble into a world where both are real.'),
  anime(52299, 'Solo Leveling', 'Ore dake Level Up na Ken', 'https://www.crunchyroll.com/imgsrv/display/thumbnail/480x720/catalog/crunchyroll/5e7f533c3b4f46244ca228af62e83dfa.jpe', 8.3, 12, ['Action', 'Fantasy'], 'A hunter at the bottom of the ranks survives a dungeon encounter and receives the power to grow stronger.'),
];

export const otherAnime = [
  anime(51009, 'Jujutsu Kaisen Season 2', 'Jujutsu Kaisen 2nd Season', tmdb('emxyWxnb15ahE9Lm9uqmwpgWLYs.jpg'), 8.8, 23, ['Action', 'Supernatural'], 'Gojo’s past and the Shibuya Incident come into focus as sorcerers face a rising threat.'),
  anime(50265, 'Spy × Family', 'Spy x Family', tmdb('pGeYGDVyHPraHqG2V3G3zIsfKCG.jpg'), 8.5, 12, ['Action', 'Comedy'], 'A spy assembles a family for an undercover mission, unaware his new wife is an assassin and his daughter can read minds.'),
  anime(47917, 'Bocchi the Rock!', 'Bocchi the Rock!', 'https://cdn.myanimelist.net/images/anime/1448/127956.jpg', 8.8, 12, ['Comedy', 'Music'], 'A talented but painfully shy guitarist finds a place in a band and learns to play in front of others.'),
];

export const mangaPicks = [
  manga(100035, 'Witch Hat Atelier', 'Tongari Boushi no Atelier', 'https://dynamic.indigoimages.ca/v1/books/books/163236770X/1.jpg?maxHeight=810&quality=85&width=810', 8.8, null, ['Adventure', 'Fantasy'], 'A dressmaker’s daughter discovers how witches cast their spells and becomes the apprentice of a traveling magician.'),
];

export const seed = [...featured, ...otherAnime, ...mangaPicks];
