package recognition

import "context"

type MockProvider struct{}

func (MockProvider) Recognize(
	_ context.Context,
	media MediaInput,
	input ProviderInput,
) (ProviderRecognition, string, error) {
	rationale := "识别到柱头与梁枋之间层层出跳、相互咬合的木构件轮廓。"
	if media.HasFocus() {
		rationale = "框选特写中可见柱头与梁枋之间层层出跳、相互咬合的木构件轮廓；整图仅用于确认其建筑位置。"
	}
	main := KnowledgeCandidateContext{}
	for _, candidate := range input.KnowledgeCandidates {
		if candidate.Name == "斗拱" {
			main = candidate
			break
		}
	}
	alternatives := make([]ProviderCandidate, 0, 2)
	for _, candidate := range input.KnowledgeCandidates {
		if candidate.Key == main.Key {
			continue
		}
		alternatives = append(alternatives, ProviderCandidate{
			CulturalElementKey: candidate.Key,
			CanonicalName:      candidate.Name,
			Category:           "其他",
			Confidence:         0.24,
			Rationale:          "这是文化内容库中的对照候选，形制与框选目标仍有明显差异。",
		})
		if len(alternatives) == 2 {
			break
		}
	}
	if len(alternatives) == 0 {
		alternatives = append(alternatives, ProviderCandidate{
			CanonicalName: "雀替",
			Category:      "建筑构件",
			Confidence:    0.31,
			Rationale:     "同样位于梁柱节点，但构件层叠方式不同。",
		})
	}
	return ProviderRecognition{
		CulturalElementKey: main.Key,
		CanonicalName:      "斗拱",
		Category:           "建筑构件",
		Confidence:         0.86,
		Summary:            "斗拱是中国传统木构建筑中承托屋檐、传递荷载的层叠构件组合。",
		Rationale:          rationale,
		Uncertainty:        "这是本地 Mock 结果，不代表真实视觉模型已分析图片。",
		TimePeriod:         "唐宋以后广泛成熟",
		Region:             "中国",
		Alternatives:       alternatives,
	}, "culturelens-mock-v5", nil
}
