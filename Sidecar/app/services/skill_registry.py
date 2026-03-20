"""
Skill Registry with Metadata-Indexed Lookup
Implements deterministic skill discovery (Phase 1 of two-phase discovery)
"""

from typing import List, Optional, Dict, Set
import re
from app.models.agent_schemas import Skill, SkillMetadata, SkillCandidate, Plugin


# =============================================================================
# Skill Registry
# =============================================================================

class SkillRegistry:
    """
    Central registry for skills with metadata-indexed lookup.
    Supports deterministic narrowing via domain/verb/noun/output-type filters.
    """
    
    def __init__(self):
        self._skills: Dict[str, Skill] = {}
        self._plugins: Dict[str, Plugin] = {}
        
        # Indexes for fast lookup
        self._domain_index: Dict[str, Set[str]] = {}  # domain -> set of skill_ids
        self._verb_index: Dict[str, Set[str]] = {}    # verb -> set of skill_ids
        self._noun_index: Dict[str, Set[str]] = {}    # noun -> set of skill_ids
        self._output_index: Dict[str, Set[str]] = {}  # output_type -> set of skill_ids
    
    def register_plugin(self, plugin: Plugin) -> None:
        """Register a plugin and all its skills"""
        self._plugins[plugin.plugin_id] = plugin
        
        for skill in plugin.skills:
            self.register_skill(skill, plugin.plugin_id)
    
    def register_skill(self, skill: Skill, plugin_id: str) -> None:
        """Register a single skill and update indexes"""
        skill_id = f"{plugin_id}.{skill.skill_id}"
        skill.plugin_id = plugin_id  # Set plugin_id on skill for later reference
        self._skills[skill_id] = skill
        
        # Update domain index
        for domain in skill.domains:
            if domain not in self._domain_index:
                self._domain_index[domain] = set()
            self._domain_index[domain].add(skill_id)
        
        # Update verb index
        for verb in skill.verbs:
            if verb not in self._verb_index:
                self._verb_index[verb] = set()
            self._verb_index[verb].add(skill_id)
        
        # Update noun index
        for noun in skill.nouns:
            if noun not in self._noun_index:
                self._noun_index[noun] = set()
            self._noun_index[noun].add(skill_id)
        
        # Update output type index
        for output_type in skill.output_types:
            if output_type not in self._output_index:
                self._output_index[output_type] = set()
            self._output_index[output_type].add(skill_id)
    
    def lookup(
        self,
        domains: Optional[List[str]] = None,
        verbs: Optional[List[str]] = None,
        nouns: Optional[List[str]] = None,
        output_types: Optional[List[str]] = None,
        auth_available: Optional[List[str]] = None,
        max_results: int = 10
    ) -> List[SkillCandidate]:
        """
        Lookup skills by metadata filters.
        Returns scored candidates sorted by relevance.
        """
        # Start with all skills
        candidate_ids = set(self._skills.keys())
        
        # Collect matching skill IDs from each index
        domain_matches = set()
        if domains:
            for domain in domains:
                domain_matches.update(self._domain_index.get(domain, set()))
        
        verb_matches = set()
        if verbs:
            for verb in verbs:
                verb_matches.update(self._verb_index.get(verb, set()))
        
        noun_matches = set()
        if nouns:
            for noun in nouns:
                noun_matches.update(self._noun_index.get(noun, set()))
        
        output_matches = set()
        if output_types:
            for output_type in output_types:
                output_matches.update(self._output_index.get(output_type, set()))
        
        # Score each candidate
        candidates = []
        for skill_id in candidate_ids:
            skill = self._skills[skill_id]
            score = 0.0
            match_reasons = []
            
            # Domain match: 3 points per match
            if domains:
                domain_overlap = set(domains) & set(skill.domains)
                if domain_overlap:
                    score += len(domain_overlap) * 3.0
                    match_reasons.append(f"Domain: {', '.join(domain_overlap)}")
            
            # Verb match: 2 points per match
            if verbs:
                verb_overlap = set(verbs) & set(skill.verbs)
                if verb_overlap:
                    score += len(verb_overlap) * 2.0
                    match_reasons.append(f"Verb: {', '.join(verb_overlap)}")
            
            # Noun match: 1 point per match
            if nouns:
                noun_overlap = set(nouns) & set(skill.nouns)
                if noun_overlap:
                    score += len(noun_overlap) * 1.0
                    match_reasons.append(f"Noun: {', '.join(noun_overlap)}")
            
            # Output type match: 1 point per match
            if output_types:
                output_overlap = set(output_types) & set(skill.output_types)
                if output_overlap:
                    score += len(output_overlap) * 1.0
                    match_reasons.append(f"Output: {', '.join(output_overlap)}")
            
            # Only include skills with non-zero score
            if score > 0:
                # Convert Skill to SkillMetadata
                metadata = SkillMetadata(
                    skill_id=skill_id,
                    plugin_id=skill_id.split('.')[0],
                    name=skill.name,
                    description=skill.description,
                    domains=skill.domains,
                    verbs=skill.verbs,
                    nouns=skill.nouns,
                    output_types=skill.output_types,
                    output_type=skill.output_type,
                    input_schema=skill.input_schema,
                    output_schema=skill.output_schema
                )
                
                candidates.append(SkillCandidate(
                    skill=metadata,
                    score=score,
                    match_reasons=match_reasons
                ))
        
        # Sort by score (descending) and return top N
        candidates.sort(key=lambda c: c.score, reverse=True)
        return candidates[:max_results]
    
    def get_skill(self, skill_id: str) -> Optional[Skill]:
        """Get a specific skill by ID"""
        return self._skills.get(skill_id)
    
    def get_plugin(self, plugin_id: str) -> Optional[Plugin]:
        """Get a specific plugin by ID"""
        return self._plugins.get(plugin_id)
    
    def get_all_plugins(self) -> List[Plugin]:
        """Get all registered plugins"""
        return list(self._plugins.values())
    
    def get_skills_for_plugin(self, plugin_id: str) -> List[Skill]:
        """Get all skills for a specific plugin"""
        plugin = self._plugins.get(plugin_id)
        if not plugin:
            return []
        return plugin.skills
    
    def get_all_domains(self) -> List[str]:
        """Get all registered domains"""
        return list(self._domain_index.keys())
    
    def get_all_verbs(self) -> List[str]:
        """Get all registered verbs"""
        return list(self._verb_index.keys())
    
    def get_all_nouns(self) -> List[str]:
        """Get all registered nouns"""
        return list(self._noun_index.keys())


# =============================================================================
# Intent Signal Extractor (Phase 1 of Discovery)
# =============================================================================

class IntentSignalExtractor:
    """
    Extracts intent signals from user queries using simple NLP.
    No LLM calls - pure deterministic extraction.
    """
    
    # Common stopwords to ignore
    STOPWORDS = {
        'a', 'an', 'and', 'are', 'as', 'at', 'be', 'by', 'for', 'from',
        'has', 'he', 'in', 'is', 'it', 'its', 'of', 'on', 'that', 'the',
        'to', 'was', 'will', 'with', 'i', 'me', 'my', 'we', 'our'
    }
    
    # Common verbs (action words)
    VERBS = {
        'list', 'get', 'fetch', 'retrieve', 'find', 'search', 'query',
        'show', 'display', 'view', 'analyze', 'compare', 'summarize',
        'create', 'add', 'update', 'delete', 'remove', 'modify',
        'send', 'post', 'put', 'patch', 'check', 'verify', 'validate'
    }
    
    # Domain keywords
    DOMAINS = {
        'github': ['github', 'git', 'repository', 'repo', 'commit', 'pr', 'pull request'],
        'http': ['http', 'https', 'api', 'endpoint', 'url', 'web', 'website'],
        'text': ['text', 'content', 'document', 'summary', 'analyze'],
    }
    
    @classmethod
    def extract(cls, query: str) -> Dict[str, List[str]]:
        """
        Extract domains, verbs, and nouns from query.
        Returns dict with keys: domains, verbs, nouns
        """
        query_lower = query.lower()
        words = re.findall(r'\b\w+\b', query_lower)
        
        # Extract domains
        domains = []
        for domain, keywords in cls.DOMAINS.items():
            for keyword in keywords:
                if keyword in query_lower:
                    domains.append(domain)
                    break
        
        # Extract verbs
        verbs = []
        for word in words:
            if word in cls.VERBS:
                verbs.append(word)
        
        # Extract nouns (words not in stopwords or verbs)
        nouns = []
        for word in words:
            if word not in cls.STOPWORDS and word not in cls.VERBS:
                if len(word) > 3:  # Filter out very short words
                    nouns.append(word)
        
        return {
            'domains': list(set(domains)),
            'verbs': list(set(verbs)),
            'nouns': list(set(nouns))
        }


# Global registry instance
_registry = SkillRegistry()


def get_registry() -> SkillRegistry:
    """Get the global skill registry instance"""
    return _registry
