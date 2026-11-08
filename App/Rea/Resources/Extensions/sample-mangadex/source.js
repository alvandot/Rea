// Sample Rea extension over the public MangaDex API.
// Contract: rea.source.{popular,latest,search,series,chapters,pages}

const BASE = "https://api.mangadex.org";

function toSeries(manga) {
  const coverRel = (manga.relationships || []).find(r => r.type === "cover_art");
  const fileName = coverRel && coverRel.attributes && coverRel.attributes.fileName;
  return {
    remoteID: manga.id,
    title: manga.attributes.title.en || Object.values(manga.attributes.title)[0] || "Untitled",
    summary: (manga.attributes.description || {}).en || "",
    coverURL: fileName
      ? `https://uploads.mangadex.org/covers/${manga.id}/${fileName}`
      : "",
    categories: (manga.attributes.tags || []).map(t => t.attributes.name.en),
  };
}

function query(params) {
  return Object.keys(params)
    .map(k => `${encodeURIComponent(k)}=${encodeURIComponent(params[k])}`)
    .join("&");
}

async function list(page, order, extra) {
  const params = Object.assign(
    {
      limit: 40,
      offset: (page - 1) * 40,
      "includes[]": "cover_art",
      "order[latestUploadedChapter]": order,
    },
    extra || {}
  );
  const res = await rea.fetch(`${BASE}/manga?${query(params)}`);
  const json = JSON.parse(res.body);
  return {
    items: (json.data || []).map(toSeries),
    hasNext: json.offset + (json.data || []).length < json.total,
  };
}

rea.source = {
  popular(page) {
    return list(page, "desc");
  },
  latest(page) {
    return list(page, "desc");
  },
  search(q, page) {
    return list(page, "desc", { title: q });
  },
  series(id) {
    return rea.fetch(`${BASE}/manga/${id}?includes[]=cover_art`).then(res => {
      const json = JSON.parse(res.body);
      return toSeries(json.data);
    });
  },
  chapters(id) {
    return rea
      .fetch(`${BASE}/manga/${id}/feed?translatedLanguage[]=en&order[chapter]=asc&limit=500`)
      .then(res => {
        const json = JSON.parse(res.body);
        return (json.data || []).map(ch => ({
          remoteID: ch.id,
          name: ch.attributes.title || `Chapter ${ch.attributes.chapter || "?"}`,
          number: parseFloat(ch.attributes.chapter || "0"),
          uploadedAt: ch.attributes.publishAt,
        }));
      });
  },
  pages(chapterID) {
    return rea.fetch(`${BASE}/at-home/server/${chapterID}`).then(res => {
      const json = JSON.parse(res.body);
      const base = `${json.baseUrl}/${json.chapter.hash}`;
      return json.chapter.data.map(name => ({ url: `${base}/${name}` }));
    });
  },
};
